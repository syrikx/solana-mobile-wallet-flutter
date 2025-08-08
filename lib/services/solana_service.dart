import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

class SolanaService {
  final String rpcUrl;
  
  SolanaService({required this.rpcUrl});
  
  // Solana 네트워크별 RPC URLs
  static const String devnetUrl = 'https://api.devnet.solana.com';
  static const String mainnetUrl = 'https://api.mainnet-beta.solana.com';
  static const String testnetUrl = 'https://api.testnet.solana.com';
  
  // RPC 호출을 위한 기본 메서드
  Future<Map<String, dynamic>> _rpcCall(
    String method,
    List<dynamic> params,
  ) async {
    final body = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': params,
    };
    
    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    
    if (response.statusCode != 200) {
      throw Exception('RPC call failed: ${response.statusCode}');
    }
    
    final result = jsonDecode(response.body);
    
    if (result.containsKey('error')) {
      throw Exception('RPC error: ${result['error']['message']}');
    }
    
    return result;
  }
  
  // 계정 잔액 조회
  Future<int> getBalance(String publicKey) async {
    final result = await _rpcCall('getBalance', [publicKey]);
    return result['result']['value'] as int;
  }
  
  // 최근 블록해시 가져오기
  Future<String> getRecentBlockhash() async {
    final result = await _rpcCall('getRecentBlockhash', []);
    return result['result']['value']['blockhash'] as String;
  }
  
  // 에어드랍 요청 (devnet/testnet에서만 작동)
  Future<String> requestAirdrop(String publicKey, int lamports) async {
    final result = await _rpcCall('requestAirdrop', [publicKey, lamports]);
    return result['result'] as String;
  }
  
  // 트랜잭션 전송
  Future<String> sendTransaction(String serializedTransaction) async {
    final result = await _rpcCall('sendTransaction', [
      serializedTransaction,
      {'encoding': 'base64', 'preflightCommitment': 'processed'}
    ]);
    return result['result'] as String;
  }
  
  // 트랜잭션 확인
  Future<Map<String, dynamic>?> confirmTransaction(
    String signature, {
    String commitment = 'confirmed',
  }) async {
    final result = await _rpcCall('getSignatureStatuses', [
      [signature],
      {'searchTransactionHistory': true}
    ]);
    
    final statuses = result['result']['value'] as List;
    if (statuses.isNotEmpty && statuses[0] != null) {
      return statuses[0] as Map<String, dynamic>;
    }
    return null;
  }
  
  // 계정의 트랜잭션 히스토리 가져오기
  Future<List<Map<String, dynamic>>> getSignaturesForAddress(
    String address, {
    int limit = 10,
  }) async {
    final result = await _rpcCall('getSignaturesForAddress', [
      address,
      {'limit': limit}
    ]);
    
    return List<Map<String, dynamic>>.from(result['result']);
  }
  
  // 트랜잭션 상세 정보 가져오기
  Future<Map<String, dynamic>?> getTransaction(String signature) async {
    try {
      final result = await _rpcCall('getTransaction', [
        signature,
        {'encoding': 'json', 'maxSupportedTransactionVersion': 0}
      ]);
      return result['result'] as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }
  
  // 최소 렌트 면제 잔액 조회
  Future<int> getMinimumBalanceForRentExemption(int dataLength) async {
    final result = await _rpcCall('getMinimumBalanceForRentExemption', [dataLength]);
    return result['result'] as int;
  }
  
  // 네트워크 상태 확인
  Future<bool> isHealthy() async {
    try {
      await _rpcCall('getHealth', []);
      return true;
    } catch (e) {
      return false;
    }
  }
}