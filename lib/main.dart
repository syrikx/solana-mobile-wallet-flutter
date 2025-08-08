import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:convert/convert.dart';
import 'dart:convert';
import 'dart:typed_data';

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
  String? publicKey;
  String? privateKeyHex;
  double? balance;
  bool isConnected = false;
  bool isLoading = false;
  
  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final String rpcUrl = 'https://api.devnet.solana.com';

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    final prefs = await SharedPreferences.getInstance();
    final mnemonic = prefs.getString('wallet_mnemonic');
    
    if (mnemonic != null) {
      await _restoreWallet(mnemonic);
    }
  }

  Future<void> _createWallet() async {
    setState(() {
      isLoading = true;
    });

    try {
      final mnemonic = bip39.generateMnemonic();
      await _restoreWallet(mnemonic);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('wallet_mnemonic', mnemonic);
      
      _showMnemonicDialog(mnemonic);
    } catch (e) {
      _showErrorDialog('지갑 생성 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _restoreWallet(String mnemonic) async {
    try {
      final seed = bip39.mnemonicToSeed(mnemonic);
      final keyData = await ED25519_HD_KEY.derivePath("m/44'/501'/0'/0'", seed);
      
      // Generate public key from private key for demo
      privateKeyHex = hex.encode(keyData.key);
      publicKey = _generateDemoPublicKey(privateKeyHex!);
      
      setState(() {
        isConnected = true;
      });
      
      await _refreshBalance();
    } catch (e) {
      _showErrorDialog('지갑 복구 실패: $e');
    }
  }
  
  String _generateDemoPublicKey(String privateKey) {
    // This is a simplified demo implementation
    // In real implementation, you'd derive the actual public key
    return '${privateKey.substring(0, 32)}Demo${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
  }

  Future<void> _refreshBalance() async {
    if (publicKey == null) return;
    
    setState(() {
      isLoading = true;
    });

    try {
      // Demo balance - in real app, you'd call Solana RPC
      // For demo purposes, showing a random balance
      balance = (DateTime.now().millisecondsSinceEpoch % 10000) / 10000.0;
      setState(() {});
    } catch (e) {
      _showErrorDialog('잔액 조회 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _requestAirdrop() async {
    if (publicKey == null) return;
    
    setState(() {
      isLoading = true;
    });

    try {
      // Demo airdrop - simulate network call
      await Future.delayed(const Duration(seconds: 2));
      
      // Add 1 SOL to balance for demo
      balance = (balance ?? 0) + 1.0;
      setState(() {});
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('1 SOL 에어드랍 성공! (데모)')),
      );
    } catch (e) {
      _showErrorDialog('에어드랍 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _sendSOL() async {
    if (publicKey == null) return;
    
    final recipient = _recipientController.text.trim();
    final amountText = _amountController.text.trim();
    
    if (recipient.isEmpty || amountText.isEmpty) {
      _showErrorDialog('받는 주소와 금액을 모두 입력해주세요.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final amount = double.parse(amountText);
      
      if (amount > (balance ?? 0)) {
        _showErrorDialog('잔액이 부족합니다.');
        return;
      }
      
      // Demo transaction simulation
      await Future.delayed(const Duration(seconds: 2));
      
      // Subtract amount from balance for demo
      balance = (balance ?? 0) - amount;
      setState(() {});
      
      _recipientController.clear();
      _amountController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전송 완료! (데모 모드)')),
      );
    } catch (e) {
      _showErrorDialog('전송 실패: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _importWallet() async {
    final controller = TextEditingController();
    
    final mnemonic = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지갑 가져오기'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '12단어 복구 구문을 입력하세요',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('가져오기'),
          ),
        ],
      ),
    );
    
    if (mnemonic != null && mnemonic.isNotEmpty) {
      try {
        await _restoreWallet(mnemonic);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('wallet_mnemonic', mnemonic);
      } catch (e) {
        _showErrorDialog('지갑 가져오기 실패: $e');
      }
    }
  }

  Future<void> _disconnectWallet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallet_mnemonic');
    
    setState(() {
      publicKey = null;
      privateKeyHex = null;
      balance = null;
      isConnected = false;
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

  void _showWalletInfo() {
    if (publicKey == null) return;
    
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
                publicKey!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: publicKey!));
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
                onPressed: isLoading ? null : _importWallet,
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
                        '주소: ${publicKey!.length > 20 ? '${publicKey!.substring(0, 20)}...' : publicKey!}',
                        style: const TextStyle(fontFamily: 'monospace'),
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

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}
