import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';

// Local imports
import 'services/solana_service.dart';
import 'services/transaction_service.dart';
import 'services/secure_storage_service.dart';
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
      title: 'Solana Mobile Wallet',
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
  SolanaWallet? wallet;
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
    await _checkBiometricSupport();
    await _loadWallet();
    _startBalanceUpdateTimer();
  }

  // 설정 불러오기
  Future<void> _loadSettings() async {
    selectedNetwork = await SecureStorageService.loadSelectedNetwork();
    solanaService = SolanaService(rpcUrl: selectedNetwork.rpcUrl);
    biometricEnabled = await SecureStorageService.isBiometricEnabled();
    transactionHistory = await SecureStorageService.loadTransactionHistory();
  }
  
  // 생체 인증 지원 확인
  Future<void> _checkBiometricSupport() async {
    if (await SecureStorageService.isBiometricAvailable()) {
      // 생체 인증 사용 가능
    }
  }
  
  // 지갑 불러오기
  Future<void> _loadWallet() async {
    try {
      wallet = await SecureStorageService.loadWallet(requireAuth: biometricEnabled);
      if (wallet != null) {
        setState(() {
          isConnected = true;
        });
        await _refreshBalance();
        await _loadTransactionHistory();
      }
    } catch (e) {
      _showErrorDialog('지갑 불러오기 실패: $e');
    }
  }

  // 새 지갑 생성
  Future<void> _createWallet() async {
    setState(() {
      isLoading = true;
    });

    try {
      final mnemonic = bip39.generateMnemonic();
      wallet = await SolanaWallet.fromMnemonic(mnemonic);
      
      await SecureStorageService.saveWallet(wallet!);
      
      setState(() {
        isConnected = true;
      });
      
      await _refreshBalance();
      _showMnemonicDialog(mnemonic);
    } catch (e) {
      _showErrorDialog('지갑 생성 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 지갑 가져오기 (니모닉으로 복원)
  Future<void> _importWallet(String mnemonic) async {
    setState(() {
      isLoading = true;
    });

    try {
      wallet = await SolanaWallet.fromMnemonic(mnemonic.trim());
      await SecureStorageService.saveWallet(wallet!);
      
      setState(() {
        isConnected = true;
      });
      
      await _refreshBalance();
      await _loadTransactionHistory();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지갑을 성공적으로 가져왔습니다!')),
      );
    } catch (e) {
      _showErrorDialog('지갑 가져오기 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 실제 블록체인에서 잔액 조회
  Future<void> _refreshBalance() async {
    if (wallet == null || solanaService == null) return;
    
    setState(() {
      isLoading = true;
    });

    try {
      final balanceLamports = await solanaService!.getBalance(wallet!.publicKeyBase58);
      setState(() {
        balance = TransactionService.lamportsToSol(balanceLamports);
      });
    } catch (e) {
      // 네트워크 연결 실패 시 이전 값 유지
      _showErrorDialog('잔액 조회 실패: 네트워크 연결을 확인해주세요');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 실제 에어드랍 요청 (개발망/테스트넷에서만 사용 가능)
  Future<void> _requestAirdrop() async {
    if (wallet == null || solanaService == null) return;
    
    if (!selectedNetwork.supportsAirdrop) {
      _showErrorDialog('마이또에서는 에어드랍을 지원하지 않습니다.');
      return;
    }
    
    setState(() {
      isLoading = true;
    });

    try {
      final signature = await solanaService!.requestAirdrop(
        wallet!.publicKeyBase58,
        TransactionService.solToLamports(1.0), // 1 SOL
      );
      
      // 트랜잭션 확인 대기
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

  // 실제 SOL 전송
  Future<void> _sendSOL() async {
    if (wallet == null || solanaService == null) return;
    
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
        fromAddress: wallet!.publicKeyBase58,
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

      // 실제 트랜잭션 생성 및 전송
      await _executeTransaction(recipient, amount);
      
    } catch (e) {
      _showErrorDialog('전송 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 니모닉 입력 대화상자 표시
  Future<void> _showImportWalletDialog() async {
    final controller = TextEditingController();
    
    final mnemonic = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지갑 가져오기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '12단어 복구 구문을 입력하세요.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'abandon ability able about above absent...',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(context, text);
              }
            },
            child: const Text('가져오기'),
          ),
        ],
      ),
    );
    
    if (mnemonic != null && mnemonic.isNotEmpty) {
      await _importWallet(mnemonic);
    }
  }

  // 추가 메서드들
  
  // 트랜잭션 실행
  Future<void> _executeTransaction(String recipient, double amount) async {
    try {
      // 최근 블록해시 가져오기
      final recentBlockhash = await solanaService!.getRecentBlockhash();
      
      // 트랜잭션 생성
      final transactionMessage = TransactionService.createTransferTransaction(
        fromPublicKey: wallet!.publicKeyBase58,
        toPublicKey: recipient,
        lamports: TransactionService.solToLamports(amount),
        recentBlockhash: recentBlockhash,
      );
      
      // 트랜잭션 서명
      final signedTransaction = TransactionService.signTransaction(
        transactionMessage,
        wallet!,
      );
      
      // 트랜잭션 전송
      final signature = await solanaService!.sendTransaction(
        TransactionService.encodeTransaction(signedTransaction),
      );
      
      // 트랜잭션 기록 추가
      final transaction = SolanaTransaction(
        signature: signature,
        timestamp: DateTime.now(),
        amount: TransactionService.solToLamports(amount),
        fromAddress: wallet!.publicKeyBase58,
        toAddress: recipient,
        status: 'pending',
      );
      
      await SecureStorageService.addTransaction(transaction);
      await _loadTransactionHistory();
      
      // 트랜잭션 확인 대기
      await _waitForTransactionConfirmation(signature);
      
      await _refreshBalance();
      
      _recipientController.clear();
      _amountController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전송 완료! 서명: ${signature.substring(0, 8)}...')),
      );
      
    } catch (e) {
      throw Exception('트랜잭션 실행 실패: $e');
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
      if (wallet != null && solanaService != null) {
        _refreshBalance();
      }
    });
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('전송'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }
  
  // 지갑 연결 해제
  Future<void> _disconnectWallet() async {
    await SecureStorageService.deleteWallet();
    
    setState(() {
      wallet = null;
      balance = null;
      isConnected = false;
      transactionHistory = [];
    });
    
    _recipientController.clear();
    _amountController.clear();
  }

  void _showMnemonicDialog(String mnemonic) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('지갑 복구 구문'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '다음 12단어를 안전한 곳에 보관하세요. 지갑을 복구할 때 필요합니다.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                mnemonic,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: mnemonic));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('복구 구문이 클립보드에 복사되었습니다')),
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
    if (wallet == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지갑 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('공개키 주소:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                wallet!.publicKeyBase58,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  biometricEnabled ? Icons.lock : Icons.lock_open,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  biometricEnabled ? '생체 인증 활성화' : '생체 인증 비활성화',
                  style: const TextStyle(fontSize: 12),
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
              Clipboard.setData(ClipboardData(text: wallet!.publicKeyBase58));
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
    if (wallet == null) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '지갑 주소 QR 코드',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              QrImageView(
                data: wallet!.publicKeyBase58,
                version: QrVersions.auto,
                size: 200.0,
              ),
              const SizedBox(height: 16),
              Text(
                wallet!.publicKeyBase58,
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
        title: const Text('Solana Mobile Wallet'),
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
                'Solana 지갑 연결',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: isLoading ? null : _createWallet,
                icon: const Icon(Icons.add),
                label: const Text('새 지갑 생성'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: isLoading ? null : _showImportWalletDialog,
                icon: const Icon(Icons.download),
                label: const Text('지갑 가져오기'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '계정 정보',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '주소: ${wallet!.publicKeyBase58.substring(0, 20)}...',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
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
                        'SOL 전송',
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
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _sendSOL,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('전송'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _disconnectWallet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                child: const Text('지갑 연결 해제'),
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

  // 네트워크 선택 대화상자
  void _showNetworkSelection() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('네트워크 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: SolanaNetwork.values.map((network) {
            return RadioListTile<SolanaNetwork>(
              title: Text(network.name),
              subtitle: Text(network.supportsAirdrop ? '에어드랍 지원' : '메인넷'),
              value: network,
              groupValue: selectedNetwork,
              onChanged: (value) {
                Navigator.pop(context, value);
              },
            );
          }).toList(),
        ),
      ),
    ).then((selectedValue) async {
      if (selectedValue != null && selectedValue != selectedNetwork) {
        setState(() {
          selectedNetwork = selectedValue;
          solanaService = SolanaService(rpcUrl: selectedNetwork.rpcUrl);
        });
        
        await SecureStorageService.saveSelectedNetwork(selectedNetwork);
        await _refreshBalance();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('네트워크가 ${selectedNetwork.name}로 변경되었습니다')),
        );
      }
    });
  }
  
  // 생체 인증 토글
  Future<void> _toggleBiometric() async {
    if (!biometricEnabled) {
      // 생체 인증 활성화
      if (await SecureStorageService.isBiometricAvailable()) {
        final authenticated = await SecureStorageService.authenticateWithBiometric(
          reason: '생체 인증을 활성화하려면 인증이 필요합니다',
        );
        
        if (authenticated) {
          setState(() {
            biometricEnabled = true;
          });
          await SecureStorageService.setBiometricEnabled(true);
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('생체 인증이 활성화되었습니다')),
          );
        }
      } else {
        _showErrorDialog('이 기기는 생체 인증을 지원하지 않습니다.');
      }
    } else {
      // 생체 인증 비활성화
      setState(() {
        biometricEnabled = false;
      });
      await SecureStorageService.setBiometricEnabled(false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('생체 인증이 비활성화되었습니다')),
      );
    }
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
