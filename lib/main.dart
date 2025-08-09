import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:app_links/app_links.dart';

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
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSettings();
    await _checkPhantomWallet();
    _startBalanceUpdateTimer();
    _initDeepLinkListener();
  }

  // 설정 불러오기
  Future<void> _loadSettings() async {
    selectedNetwork = await SecureStorageService.loadSelectedNetwork();
    solanaService = SolanaService(rpcUrl: selectedNetwork.rpcUrl);
    phantomWalletService = PhantomWalletService();
    biometricEnabled = await SecureStorageService.isBiometricEnabled();
    transactionHistory = await SecureStorageService.loadTransactionHistory();
  }

  // 딥링크 리스너 초기화
  void _initDeepLinkListener() {
    final appLinks = AppLinks();
    
    // 앱이 실행 중일 때 들어오는 딥링크 처리
    _linkSubscription = appLinks.uriLinkStream.listen(
      (Uri uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        print('Deep link error: $err');
      },
    );
  }

  // 딥링크 처리
  void _handleDeepLink(Uri uri) {
    print('Received deep link: $uri');
    
    if (uri.scheme == 'solana_wallet_flutter') {
      if (uri.host == 'connected') {
        _handlePhantomConnectionCallback(uri);
      } else if (uri.host == 'signed') {
        _handlePhantomTransactionCallback(uri);
      }
    }
  }

  // Phantom 연결 콜백 처리
  void _handlePhantomConnectionCallback(Uri uri) {
    try {
      final queryParams = uri.queryParameters;
      final publicKey = queryParams['phantom_encryption_public_key'];
      
      if (publicKey != null && publicKey.isNotEmpty) {
        _processPhantomConnection(publicKey);
      } else {
        final errorCode = queryParams['errorCode'];
        final errorMessage = queryParams['errorMessage'] ?? '알 수 없는 오류';
        _showErrorDialog('Phantom 연결 실패: $errorMessage (코드: $errorCode)');
      }
    } catch (e) {
      _showErrorDialog('딥링크 처리 중 오류: $e');
    }
  }

  // Phantom 트랜잭션 콜백 처리  
  void _handlePhantomTransactionCallback(Uri uri) {
    try {
      final queryParams = uri.queryParameters;
      final signature = queryParams['signature'];
      
      if (signature != null && signature.isNotEmpty) {
        _processPhantomTransactionSuccess(signature);
      } else {
        final errorCode = queryParams['errorCode'];
        final errorMessage = queryParams['errorMessage'] ?? '알 수 없는 오류';
        _showErrorDialog('Phantom 트랜잭션 실패: $errorMessage (코드: $errorCode)');
      }
    } catch (e) {
      _showErrorDialog('트랜잭션 콜백 처리 중 오류: $e');
    }
  }

  // 실제 Phantom 연결 처리
  Future<void> _processPhantomConnection(String publicKey) async {
    try {
      phantomWalletService?.setConnectedWallet(publicKey);
      connectedWallet = PhantomWallet.fromAddress(publicKey);
      
      // 연결 정보 저장
      await SecureStorageService.saveWalletData({
        'phantom_address': publicKey,
        'phantom_label': 'Phantom Wallet (Real)',
        'connected_at': DateTime.now().millisecondsSinceEpoch,
      });
      
      setState(() {
        isConnected = true;
        isLoading = false;
      });
      
      await _refreshBalance();
      await _loadTransactionHistory();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phantom 지갑이 연결되었습니다!\\n주소: ${publicKey.substring(0, 8)}...')),
      );
    } catch (e) {
      _showErrorDialog('Phantom 연결 처리 중 오류: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  // 실제 Phantom 트랜잭션 성공 처리
  Future<void> _processPhantomTransactionSuccess(String signature) async {
    try {
      // 트랜잭션 확인 대기
      await _waitForTransactionConfirmation(signature);
      
      // 잔액 새로고침
      await _refreshBalance();
      await _loadTransactionHistory();
      
      // 입력 필드 초기화
      _recipientController.clear();
      _amountController.clear();
      
      setState(() {
        isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('트랜잭션이 성공적으로 전송되었습니다!\\n서명: ${signature.substring(0, 8)}...')),
      );
    } catch (e) {
      _showErrorDialog('트랜잭션 처리 중 오류: $e');
      setState(() {
        isLoading = false;
      });
    }
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
      // Phantom 앱에 바로 연결 요청 (설치 확인 생략)
      final result = await phantomWalletService!.connectWallet();
      
      // 연결 대기 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          duration: const Duration(seconds: 5),
        ),
      );
      
      // 실제 Phantom 응답을 기다림 (딥링크 콜백으로 처리)
      
    } catch (e) {
      final errorMessage = e.toString();
      if (errorMessage.contains('실행할 수 없습니다')) {
        // Phantom 설치/업데이트 필요한 경우 특별 처리
        _showPhantomInstallDialog();
      } else {
        _showErrorDialog('Phantom 지갑 연결 실패: $e');
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
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
      
      // 실제 Phantom 응답을 기다림 (딥링크 콜백으로 처리)
      
    } catch (e) {
      throw Exception('Phantom 트랜잭션 실행 실패: $e');
    }
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
  
  // Phantom 설치/업데이트 대화상자
  Future<void> _showPhantomInstallDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🦄 Phantom 지갑 필요'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phantom 지갑을 실행할 수 없습니다.'),
            SizedBox(height: 12),
            Text('다음을 확인해주세요:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• Phantom 앱이 설치되어 있나요?'),
            Text('• 최신 버전으로 업데이트되어 있나요?'),
            Text('• 앱이 정상적으로 작동하나요?'),
            SizedBox(height: 12),
            Text('Play Store에서 Phantom을 설치하거나 업데이트한 후 다시 시도해주세요.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await PhantomWalletService.openPhantomInstallPage();
            },
            child: const Text('Play Store 열기'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _connectToPhantom(); // 다시 시도
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
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
                        'Phantom 앱을 실행하여 연결을 승인해주세요.\n\n앱이 실행되지 않으면 Play Store에서\nPhantom을 설치하거나 업데이트해주세요.',
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
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => PhantomWalletService.openPhantomInstallPage(),
                        icon: const Icon(Icons.download),
                        label: const Text('Phantom 설치/업데이트'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purple,
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
    _linkSubscription?.cancel();
    super.dispose();
  }
}