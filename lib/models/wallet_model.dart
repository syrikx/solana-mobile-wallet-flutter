import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:convert/convert.dart';

class SolanaWallet {
  final String publicKey;
  final String privateKey;
  final String mnemonic;
  final Uint8List privateKeyBytes;
  
  SolanaWallet({
    required this.publicKey,
    required this.privateKey,
    required this.mnemonic,
    required this.privateKeyBytes,
  });
  
  // Base58 encoding/decoding 구현
  static const String _base58Alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  
  static String encodeBase58(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    
    List<int> digits = [0];
    
    for (int byte in bytes) {
      int carry = byte;
      for (int i = 0; i < digits.length; i++) {
        carry += digits[i] << 8;
        digits[i] = carry % 58;
        carry ~/= 58;
      }
      while (carry > 0) {
        digits.add(carry % 58);
        carry ~/= 58;
      }
    }
    
    // Handle leading zeros
    int leadingZeros = 0;
    for (int byte in bytes) {
      if (byte == 0) {
        leadingZeros++;
      } else {
        break;
      }
    }
    
    String result = '';
    for (int i = 0; i < leadingZeros; i++) {
      result += _base58Alphabet[0];
    }
    
    for (int i = digits.length - 1; i >= 0; i--) {
      result += _base58Alphabet[digits[i]];
    }
    
    return result;
  }
  
  static Uint8List decodeBase58(String encoded) {
    if (encoded.isEmpty) return Uint8List(0);
    
    List<int> decoded = [0];
    
    for (int i = 0; i < encoded.length; i++) {
      int carry = _base58Alphabet.indexOf(encoded[i]);
      if (carry < 0) throw ArgumentError('Invalid Base58 character');
      
      for (int j = 0; j < decoded.length; j++) {
        carry += decoded[j] * 58;
        decoded[j] = carry & 0xff;
        carry >>= 8;
      }
      
      while (carry > 0) {
        decoded.add(carry & 0xff);
        carry >>= 8;
      }
    }
    
    // Handle leading 1s
    int leadingOnes = 0;
    for (int i = 0; i < encoded.length && encoded[i] == _base58Alphabet[0]; i++) {
      leadingOnes++;
    }
    
    List<int> result = List.filled(leadingOnes, 0);
    result.addAll(decoded.reversed);
    
    return Uint8List.fromList(result);
  }
  
  // Public key를 Base58로 인코딩
  String get publicKeyBase58 {
    return publicKey;
  }
  
  // 트랜잭션 서명
  Uint8List signTransaction(Uint8List transactionBytes) {
    // Ed25519 서명 구현 필요
    // 여기서는 간단히 privateKeyBytes를 사용
    return Uint8List.fromList([...privateKeyBytes.take(64)]);
  }
  
  // 메시지 서명
  Uint8List signMessage(String message) {
    final messageBytes = utf8.encode(message);
    // Ed25519 서명 구현 필요
    return Uint8List.fromList([...privateKeyBytes.take(64)]);
  }
  
  // 지갑 정보를 JSON으로 직렬화 (보안상 privateKey 제외)
  Map<String, dynamic> toJson() {
    return {
      'publicKey': publicKey,
      'mnemonic': mnemonic,
      // privateKey는 보안상 저장하지 않음
    };
  }
  
  // JSON에서 지갑 복원 (mnemonic 필요)
  static Future<SolanaWallet> fromMnemonic(String mnemonic) async {
    // BIP39 시드 생성
    final seed = await _mnemonicToSeed(mnemonic);
    
    // Solana의 표준 derivation path: m/44'/501'/0'/0'
    final keyData = await ED25519_HD_KEY.derivePath("m/44'/501'/0'/0'", seed);
    
    // 공개키 생성 (처음 32바이트가 private key, 마지막 32바이트가 public key)
    final privateKeyBytes = Uint8List.fromList(keyData.key.take(32).toList());
    final publicKeyBytes = Uint8List.fromList(keyData.key.skip(32).take(32).toList());
    
    final publicKeyBase58 = encodeBase58(publicKeyBytes);
    final privateKeyHex = hex.encode(privateKeyBytes);
    
    return SolanaWallet(
      publicKey: publicKeyBase58,
      privateKey: privateKeyHex,
      mnemonic: mnemonic,
      privateKeyBytes: privateKeyBytes,
    );
  }
  
  // 니모닉을 시드로 변환하는 간단한 구현
  static Future<Uint8List> _mnemonicToSeed(String mnemonic) async {
    final mnemonicBytes = utf8.encode(mnemonic);
    final saltBytes = utf8.encode('mnemonic');
    
    // PBKDF2를 사용하여 시드 생성
    final key = await _pbkdf2(mnemonicBytes, saltBytes, 2048, 64);
    return key;
  }
  
  // PBKDF2 구현
  static Future<Uint8List> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) async {
    final hmac = Hmac(sha512, password);
    final result = <int>[];
    
    int blocks = (keyLength / 64).ceil();
    
    for (int block = 1; block <= blocks; block++) {
      final blockSalt = [...salt, ...[(block >> 24) & 0xff, (block >> 16) & 0xff, (block >> 8) & 0xff, block & 0xff]];
      
      var u = hmac.convert(blockSalt).bytes;
      var f = [...u];
      
      for (int i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (int j = 0; j < f.length; j++) {
          f[j] ^= u[j];
        }
      }
      
      result.addAll(f);
    }
    
    return Uint8List.fromList(result.take(keyLength).toList());
  }
}

// 트랜잭션 데이터 모델
class SolanaTransaction {
  final String signature;
  final DateTime timestamp;
  final int amount;
  final String fromAddress;
  final String toAddress;
  final String status;
  final int? blockTime;
  final int? slot;
  final String? error;
  
  SolanaTransaction({
    required this.signature,
    required this.timestamp,
    required this.amount,
    required this.fromAddress,
    required this.toAddress,
    required this.status,
    this.blockTime,
    this.slot,
    this.error,
  });
  
  factory SolanaTransaction.fromJson(Map<String, dynamic> json) {
    return SolanaTransaction(
      signature: json['signature'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['blockTime'] ?? 0) * 1000,
      ),
      amount: json['amount'] ?? 0,
      fromAddress: json['fromAddress'] ?? '',
      toAddress: json['toAddress'] ?? '',
      status: json['confirmationStatus'] ?? 'unknown',
      blockTime: json['blockTime'],
      slot: json['slot'],
      error: json['error'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'signature': signature,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'amount': amount,
      'fromAddress': fromAddress,
      'toAddress': toAddress,
      'status': status,
      'blockTime': blockTime,
      'slot': slot,
      'error': error,
    };
  }
}

// 네트워크 설정 모델
enum SolanaNetwork {
  mainnet,
  devnet,
  testnet,
}

extension SolanaNetworkExtension on SolanaNetwork {
  String get name {
    switch (this) {
      case SolanaNetwork.mainnet:
        return 'Mainnet';
      case SolanaNetwork.devnet:
        return 'Devnet';
      case SolanaNetwork.testnet:
        return 'Testnet';
    }
  }
  
  String get rpcUrl {
    switch (this) {
      case SolanaNetwork.mainnet:
        return 'https://api.mainnet-beta.solana.com';
      case SolanaNetwork.devnet:
        return 'https://api.devnet.solana.com';
      case SolanaNetwork.testnet:
        return 'https://api.testnet.solana.com';
    }
  }
  
  bool get supportsAirdrop {
    return this != SolanaNetwork.mainnet;
  }
}