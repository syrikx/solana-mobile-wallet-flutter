import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Local imports
import 'services/solana_service.dart';
import 'services/transaction_service.dart';
import 'services/secure_storage_service.dart';
import 'services/phantom_wallet_service.dart';
import 'models/wallet_model.dart';

import 'dart:async';

void main() {
  runApp(const SolanaWalletApp());
}

class SolanaWalletApp extends StatelessWidget {
  const SolanaWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solana Phantom Wallet',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const WalletHomePage(),
    );
  }
}

class WalletHomePage extends StatefulWidget {
  const WalletHomePage({super.key});

  @override
  State<WalletHomePage> createState() => _WalletHomePageState();
}

class _WalletHomePageState extends State<WalletHomePage> {
  PhantomWalletService? phantomWalletService;
  PhantomWallet? connectedWallet;
  SolanaService? solanaService;
  SolanaNetwork selectedNetwork = SolanaNetwork.devnet;
  double? balance;
  bool isConnected = false;
  bool isLoading = false;
  bool biometricEnabled = false;
  List<SolanaTransaction> transactionHistory = [];
  
  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _balanceUpdateTimer;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSettings();
    await _checkPhantomWallet();
    _startBalanceUpdateTimer();
  }

  // 설정 불러오기
  Future<void> _loadSettings() async {
    selectedNetwork = await SecureStorageService.loadSelectedNetwork();
    solanaService = SolanaService(rpcUrl: selectedNetwork.rpcUrl);
    phantomWalletService = PhantomWalletService();
    biometricEnabled = await SecureStorageService.isBiometricEnabled();
    transactionHistory = await SecureStorageService.loadTransactionHistory();
  }
  
  // Phantom 지갑 설치 및 연결 상태 확인
  Future<void> _checkPhantomWallet() async {
    try {
      // 저장된 연결 정보가 있는지 확인
      await _checkStoredConnection();
    } catch (e) {
      // 오류는 무시 (수동 연결 가능)
    }
  }
  
  // 저장된 연결 정보 확인
  Future<void> _checkStoredConnection() async {
    try {
      final walletData = await SecureStorageService.loadWalletData();
      if (walletData != null && walletData['phantom_address'] != null) {
        // 저장된 Phantom 주소로 자동 연결 시도
        final address = walletData['phantom_address'] as String;
        phantomWalletService?.setConnectedWallet(address);
        connectedWallet = PhantomWallet.fromAddress(address);
        
        setState(() {
          isConnected = true;
        });
        
        await _refreshBalance();
        await _loadTransactionHistory();
      }
    } catch (e) {
      // 자동 재연결 실패는 무시
    }
  }

  // Phantom 지갑 연결 (딥링크 방식)
  Future<void> _connectToPhantom() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Phantom 설치 확인
      final isInstalled = await PhantomWalletService.isPhantomWalletInstalled();
      if (!isInstalled) {
        final install = await _showInstallDialog();
        if (install) {
          await PhantomWalletService.openPhantomInstallPage();
        }
        return;
      }
      
      // Phantom 앱에 연결 요청
      final result = await phantomWalletService!.connectWallet();
      
      // 연결 대기 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          duration: const Duration(seconds: 5),
        ),
      );
      
      // 데모용으로 임시 지갑 주소 생성 (실제로는 Phantom에서 콜백 받아야 함)
      await Future.delayed(const Duration(seconds: 2));
      await _simulatePhantomConnection();
      
    } catch (e) {
      _showErrorDialog('Phantom 지갑 연결 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }
  
  // 데모용 Phantom 연결 시뮬레이션
  Future<void> _simulatePhantomConnection() async {
    // 실제 환경에서는 Phantom 앱에서 딥링크 콜백을 통해 주소를 받아옴
    // 여기서는 데모용으로 임시 주소 생성
    const demoAddress = '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU';
    
    phantomWalletService?.setConnectedWallet(demoAddress);
    connectedWallet = PhantomWallet.fromAddress(demoAddress);
    
    // 연결 정보 저장
    await SecureStorageService.saveWalletData({
      'phantom_address': demoAddress,
      'phantom_label': 'Phantom Wallet',
      'connected_at': DateTime.now().millisecondsSinceEpoch,
    });
    
    setState(() {
      isConnected = true;
    });
    
    await _refreshBalance();
    await _loadTransactionHistory();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Phantom 지갑이 연결되었습니다!\n주소: ${demoAddress.substring(0, 8)}...')),
    );
  }

  // 실제 블록체인에서 잔액 조회
  Future<void> _refreshBalance() async {
    if (connectedWallet == null || solanaService == null) return;
    
    setState(() {
      isLoading = true;
    });

    try {
      final balanceLamports = await solanaService!.getBalance(connectedWallet!.address);
      setState(() {
        balance = TransactionService.lamportsToSol(balanceLamports);
      });
    } catch (e) {
      _showErrorDialog('잔액 조회 실패: 네트워크 연결을 확인해주세요');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 실제 에어드랍 요청
  Future<void> _requestAirdrop() async {
    if (connectedWallet == null || solanaService == null) return;
    
    if (!selectedNetwork.supportsAirdrop) {
      _showErrorDialog('메인넷에서는 에어드랍을 지원하지 않습니다.');
      return;
    }
    
    setState(() {
      isLoading = true;
    });

    try {
      final signature = await solanaService!.requestAirdrop(
        connectedWallet!.address,
        TransactionService.solToLamports(1.0), // 1 SOL
      );
      
      await _waitForTransactionConfirmation(signature);
      await _refreshBalance();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('1 SOL 에어드랍 성공!')),
      );
    } catch (e) {
      _showErrorDialog('에어드랍 실패: $e\n\n에어드랍은 하루에 제한된 횟수만 가능합니다.');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Phantom을 통한 SOL 전송
  Future<void> _sendSOL() async {
    if (connectedWallet == null || phantomWalletService == null) return;
    
    final recipient = _recipientController.text.trim();
    final amountText = _amountController.text.trim();
    
    if (recipient.isEmpty || amountText.isEmpty) {
      _showErrorDialog('받는 주소와 금액을 모두 입력해주세요.');
      return;
    }

    try {
      final amount = double.parse(amountText);
      final currentBalance = TransactionService.solToLamports(balance ?? 0);
      
      // 트랜잭션 시뮬레이션
      final simulation = TransactionService.simulateTransaction(
        fromAddress: connectedWallet!.address,
        toAddress: recipient,
        solAmount: amount,
        currentBalance: currentBalance,
      );
      
      if (!simulation['success']) {
        _showErrorDialog(simulation['error']);
        return;
      }
      
      // 전송 확인 대화상자
      final confirmed = await _showTransactionConfirmationDialog(
        recipient: recipient,
        amount: amount,
        estimatedFee: TransactionService.lamportsToSol(simulation['estimatedFee']),
      );
      
      if (!confirmed) return;
      
      setState(() {
        isLoading = true;
      });

      // Phantom을 통한 트랜잭션 실행 (딥링크)
      await _executePhantomTransaction(recipient, amount);
      
    } catch (e) {
      _showErrorDialog('전송 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Phantom을 통한 트랜잭션 실행 (딥링크)
  Future<void> _executePhantomTransaction(String recipient, double amount) async {
    try {
      // 최근 블록해시 가져오기
      final recentBlockhash = await solanaService!.getRecentBlockhash();
      
      // 트랜잭션 생성
      final transactionMessage = TransactionService.createTransferTransaction(
        fromPublicKey: connectedWallet!.address,
        toPublicKey: recipient,
        lamports: TransactionService.solToLamports(amount),
        recentBlockhash: recentBlockhash,
      );
      
      // Base64로 인코딩
      final encodedTransaction = TransactionService.encodeTransaction(transactionMessage);
      
      // Phantom에 트랜잭션 서명 및 전송 요청
      final result = await phantomWalletService!.signAndSendTransaction(encodedTransaction);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'])),
      );
      
      // 데모용으로 성공 처리 (실제로는 Phantom에서 콜백 받아야 함)
      await Future.delayed(const Duration(seconds: 3));
      await _simulateTransactionSuccess(recipient, amount);
      
    } catch (e) {
      throw Exception('Phantom 트랜잭션 실행 실패: $e');
    }
  }
  
  // 데모용 트랜잭션 성공 시뮬레이션
  Future<void> _simulateTransactionSuccess(String recipient, double amount) async {
    // 임시 서명 생성
    const signature = '3Kd8jkvKJ1234567890abcdefghijklmnopqrstuvwxyz';
    
    // 트랜잭션 기록 추가
    final transaction = SolanaTransaction(
      signature: signature,
      timestamp: DateTime.now(),
      amount: TransactionService.solToLamports(amount),
      fromAddress: connectedWallet!.address,
      toAddress: recipient,
      status: 'confirmed',
    );
    
    await SecureStorageService.addTransaction(transaction);
    await _loadTransactionHistory();
    await _refreshBalance();
    
    _recipientController.clear();
    _amountController.clear();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('전송 완료! 서명: ${signature.substring(0, 8)}...')),
    );
  }
  
  // 트랜잭션 확인 대기
  Future<void> _waitForTransactionConfirmation(String signature) async {
    int attempts = 0;
    const maxAttempts = 30; // 30초 대기
    
    while (attempts < maxAttempts) {
      try {
        final status = await solanaService!.confirmTransaction(signature);
        if (status != null && status['confirmationStatus'] == 'confirmed') {
          return;
        }
        
        await Future.delayed(const Duration(seconds: 1));
        attempts++;
      } catch (e) {
        await Future.delayed(const Duration(seconds: 1));
        attempts++;
      }
    }
  }
  
  // 트랜잭션 히스토리 불러오기
  Future<void> _loadTransactionHistory() async {
    try {
      transactionHistory = await SecureStorageService.loadTransactionHistory();
      setState(() {});
    } catch (e) {
      // 히스토리 로딩 실패는 무시
    }
  }
  
  // 잔액 자동 업데이트 타이머 시작
  void _startBalanceUpdateTimer() {
    _balanceUpdateTimer?.cancel();
    _balanceUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (connectedWallet != null && solanaService != null) {
        _refreshBalance();
      }
    });
  }
  
  // Phantom 설치 확인 대화상자
  Future<bool> _showInstallDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Phantom 지갑이 필요합니다'),
        content: const Text('Phantom 지갑 앱이 설치되어 있지 않습니다.\nGoogle Play Store에서 Phantom을 설치하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('설치하러 가기'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }
  
  // 트랜잭션 확인 대화상자
  Future<bool> _showTransactionConfirmationDialog({
    required String recipient,
    required double amount,
    required double estimatedFee,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전송 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('받는 주소: ${recipient.substring(0, 8)}...${recipient.substring(recipient.length - 8)}'),
            const SizedBox(height: 8),
            Text('전송 금액: $amount SOL'),
            const SizedBox(height: 8),
            Text('예상 수수료: $estimatedFee SOL'),
            const SizedBox(height: 8),
            Text('총 비용: ${amount + estimatedFee} SOL', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Phantom 지갑에서 트랜잭션을 확인하고 승인해주세요.', 
                 style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Phantom에서 승인'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }
  
  // Phantom 지갑 연결 해제
  Future<void> _disconnectWallet() async {
    try {
      await phantomWalletService?.disconnectWallet();
      await SecureStorageService.deleteWallet();
      
      setState(() {
        connectedWallet = null;
        balance = null;
        isConnected = false;
        transactionHistory = [];
      });
      
      _recipientController.clear();
      _amountController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phantom 지갑 연결이 해제되었습니다.')),
      );
    } catch (e) {
      _showErrorDialog('지갑 연결 해제 실패: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  // 지갑 정보 대화상자 표시
  void _showWalletInfo() {
    if (connectedWallet == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Phantom 지갑 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('지갑 주소:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                connectedWallet!.address,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            const Text('네트워크:'),
            const SizedBox(height: 4),
            Text(
              selectedNetwork.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('연결된 지갑:'),
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.account_balance_wallet, size: 16, color: Colors.purple),
                SizedBox(width: 4),
                Text(
                  'Phantom Wallet (딥링크)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _showQRCode(),
            child: const Text('QR 코드'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: connectedWallet!.address));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('주소가 클립보드에 복사되었습니다')),
              );
            },
            child: const Text('복사'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
  
  // QR 코드 표시
  void _showQRCode() {
    if (connectedWallet == null) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Phantom 지갑 주소 QR 코드',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              QrImageView(
                data: connectedWallet!.address,
                version: QrVersions.auto,
                size: 200.0,
              ),
              const SizedBox(height: 16),
              Text(
                connectedWallet!.address,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solana Phantom Wallet'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.info),
              onPressed: _showWalletInfo,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isConnected) ...[ 
              const Text(
                '🦄 Phantom 지갑 연결',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Phantom 지갑 딥링크를 통해 안전하게 Solana 네트워크에 연결하세요',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.account_balance_wallet, size: 64, color: Colors.purple),
                      const SizedBox(height: 16),
                      const Text(
                        'Phantom 지갑 연결 (딥링크)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Phantom 앱이 설치되어 있어야 합니다.\n딥링크를 통해 Phantom 앱에서 연결을 승인해주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: isLoading ? null : _connectToPhantom,
                        icon: const Icon(Icons.link),
                        label: const Text('Phantom 지갑 연결'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[ 
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.account_balance_wallet, color: Colors.purple),
                          SizedBox(width: 8),
                          Text(
                            'Phantom 지갑 연결됨 (딥링크)',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '주소: ${connectedWallet!.address.substring(0, 20)}...',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.network_check,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            selectedNetwork.name,
                            style: const TextStyle(fontSize: 12, color: Colors.green),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '잔액: ${balance?.toStringAsFixed(4) ?? '로딩중...'} SOL',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            onPressed: isLoading ? null : _refreshBalance,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      if (selectedNetwork.supportsAirdrop) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isLoading ? null : _requestAirdrop,
                                child: const Text('테스트넷 SOL 받기'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SOL 전송 (Phantom 딥링크)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _recipientController,
                        decoration: const InputDecoration(
                          labelText: '받는 주소',
                          border: OutlineInputBorder(),
                          hintText: '공개키 주소를 입력하세요',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                          labelText: '금액 (SOL)',
                          border: OutlineInputBorder(),
                          hintText: '전송할 SOL 금액',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : _sendSOL,
                          icon: const Icon(Icons.send),
                          label: const Text('Phantom에서 전송 승인'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _disconnectWallet,
                icon: const Icon(Icons.link_off),
                label: const Text('Phantom 지갑 연결 해제'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
            
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _connectivitySubscription?.cancel();
    _balanceUpdateTimer?.cancel();
    super.dispose();
  }
}