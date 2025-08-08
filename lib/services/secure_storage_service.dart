import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../models/wallet_model.dart';

class SecureStorageService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  
  static final LocalAuthentication _localAuth = LocalAuthentication();
  
  // Storage keys
  static const String _walletKey = 'solana_wallet';
  static const String _networkKey = 'selected_network';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _transactionHistoryKey = 'transaction_history';
  
  // 생체 인증 지원 여부 확인
  static Future<bool> isBiometricAvailable() async {
    try {
      final isAvailable = await _localAuth.isDeviceSupported();
      final isEnabled = await _localAuth.canCheckBiometrics;
      return isAvailable && isEnabled;
    } catch (e) {
      return false;
    }
  }
  
  // 등록된 생체 인증 목록 가져오기
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }
  
  // 생체 인증으로 앱 잠금 해제
  static Future<bool> authenticateWithBiometric({
    String reason = '지갑에 액세스하려면 인증이 필요합니다',
  }) async {
    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      return isAuthenticated;
    } catch (e) {
      return false;
    }
  }
  
  // 지갑 정보 안전하게 저장 (기존 SolanaWallet용)
  static Future<bool> saveWallet(SolanaWallet wallet) async {
    try {
      final walletData = {
        'mnemonic': wallet.mnemonic,
        'publicKey': wallet.publicKey,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      
      await _secureStorage.write(
        key: _walletKey,
        value: jsonEncode(walletData),
      );
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // Phantom 지갑 연결 정보 저장
  static Future<bool> saveWalletData(Map<String, dynamic> walletData) async {
    try {
      await _secureStorage.write(
        key: _walletKey,
        value: jsonEncode(walletData),
      );
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // 지갑 정보 불러오기
  static Future<Map<String, dynamic>?> loadWalletData() async {
    try {
      final walletJson = await _secureStorage.read(key: _walletKey);
      if (walletJson != null) {
        return jsonDecode(walletJson) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  // 지갑 복원 (생체 인증 포함)
  static Future<SolanaWallet?> loadWallet({bool requireAuth = false}) async {
    try {
      if (requireAuth) {
        final biometricEnabled = await isBiometricEnabled();
        if (biometricEnabled) {
          final authenticated = await authenticateWithBiometric();
          if (!authenticated) {
            return null;
          }
        }
      }
      
      final walletData = await loadWalletData();
      if (walletData != null && walletData['mnemonic'] != null) {
        return await SolanaWallet.fromMnemonic(walletData['mnemonic']);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  // 지갑 삭제
  static Future<bool> deleteWallet() async {
    try {
      await _secureStorage.delete(key: _walletKey);
      await _secureStorage.delete(key: _transactionHistoryKey);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // 생체 인증 설정 저장
  static Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(
      key: _biometricEnabledKey,
      value: enabled.toString(),
    );
  }
  
  // 생체 인증 설정 확인
  static Future<bool> isBiometricEnabled() async {
    final enabled = await _secureStorage.read(key: _biometricEnabledKey);
    return enabled == 'true';
  }
  
  // 네트워크 설정 저장
  static Future<void> saveSelectedNetwork(SolanaNetwork network) async {
    await _secureStorage.write(
      key: _networkKey,
      value: network.index.toString(),
    );
  }
  
  // 네트워크 설정 불러오기
  static Future<SolanaNetwork> loadSelectedNetwork() async {
    final networkIndex = await _secureStorage.read(key: _networkKey);
    if (networkIndex != null) {
      final index = int.tryParse(networkIndex) ?? 0;
      return SolanaNetwork.values[index];
    }
    return SolanaNetwork.devnet; // 기본값
  }
  
  // 트랜잭션 히스토리 저장
  static Future<void> saveTransactionHistory(List<SolanaTransaction> transactions) async {
    try {
      final historyData = transactions.map((tx) => tx.toJson()).toList();
      await _secureStorage.write(
        key: _transactionHistoryKey,
        value: jsonEncode(historyData),
      );
    } catch (e) {
      // 히스토리 저장 실패는 무시 (중요하지 않음)
    }
  }
  
  // 트랜잭션 히스토리 불러오기
  static Future<List<SolanaTransaction>> loadTransactionHistory() async {
    try {
      final historyJson = await _secureStorage.read(key: _transactionHistoryKey);
      if (historyJson != null) {
        final historyData = jsonDecode(historyJson) as List;
        return historyData
            .map((data) => SolanaTransaction.fromJson(data))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  
  // 트랜잭션 히스토리에 새 트랜잭션 추가
  static Future<void> addTransaction(SolanaTransaction transaction) async {
    final history = await loadTransactionHistory();
    history.insert(0, transaction); // 최신순 정렬
    
    // 최대 100개까지만 저장
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }
    
    await saveTransactionHistory(history);
  }
  
  // 모든 데이터 삭제 (앱 초기화)
  static Future<void> clearAllData() async {
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      // 개별적으로 삭제 시도
      await deleteWallet();
      await _secureStorage.delete(key: _networkKey);
      await _secureStorage.delete(key: _biometricEnabledKey);
      await _secureStorage.delete(key: _transactionHistoryKey);
    }
  }
  
  // 저장된 지갑 존재 여부 확인
  static Future<bool> hasWallet() async {
    final walletData = await loadWalletData();
    return walletData != null && walletData['mnemonic'] != null;
  }
}