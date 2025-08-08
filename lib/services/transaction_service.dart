import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import '../models/wallet_model.dart';

class TransactionService {
  // SOL을 lamports로 변환
  static int solToLamports(double sol) {
    return (sol * 1000000000).round();
  }
  
  // Lamports를 SOL로 변환
  static double lamportsToSol(int lamports) {
    return lamports / 1000000000;
  }
  
  // 기본 SOL 전송 트랜잭션 생성
  static Uint8List createTransferTransaction({
    required String fromPublicKey,
    required String toPublicKey,
    required int lamports,
    required String recentBlockhash,
  }) {
    // Solana 트랜잭션 구조를 바이트로 직렬화
    // 실제 구현에서는 더 복잡한 트랜잭션 구조가 필요
    
    final fromBytes = SolanaWallet.decodeBase58(fromPublicKey);
    final toBytes = SolanaWallet.decodeBase58(toPublicKey);
    final blockhashBytes = _base58Decode(recentBlockhash);
    
    // 간단한 전송 명령어 구성
    final instruction = _createSystemTransferInstruction(
      fromBytes,
      toBytes,
      lamports,
    );
    
    // 트랜잭션 메시지 구성
    final message = _createTransactionMessage(
      [instruction],
      fromBytes,
      blockhashBytes,
    );
    
    return message;
  }
  
  // System Program의 Transfer 명령어 생성
  static Map<String, dynamic> _createSystemTransferInstruction(
    Uint8List from,
    Uint8List to,
    int lamports,
  ) {
    // System Program ID
    final systemProgramId = Uint8List.fromList(List.filled(32, 0));
    
    // Transfer 명령어 데이터 (instruction discriminator + lamports)
    final instructionData = ByteData(12);
    instructionData.setUint32(0, 2, Endian.little); // Transfer instruction
    instructionData.setUint64(4, lamports, Endian.little);
    
    return {
      'programId': systemProgramId,
      'accounts': [
        {'pubkey': from, 'isSigner': true, 'isWritable': true},
        {'pubkey': to, 'isSigner': false, 'isWritable': true},
      ],
      'data': instructionData.buffer.asUint8List(),
    };
  }
  
  // 트랜잭션 메시지 생성
  static Uint8List _createTransactionMessage(
    List<Map<String, dynamic>> instructions,
    Uint8List feePayer,
    Uint8List recentBlockhash,
  ) {
    final message = <int>[];
    
    // Header
    message.add(1); // numRequiredSignatures
    message.add(0); // numReadonlySignedAccounts
    message.add(1); // numReadonlyUnsignedAccounts
    
    // Account keys
    final accountKeys = <Uint8List>[];
    final accountMeta = <Map<String, bool>>[];
    
    // Fee payer (첫 번째 계정)
    accountKeys.add(feePayer);
    accountMeta.add({'isSigner': true, 'isWritable': true});
    
    // 명령어에서 계정들 수집
    for (final instruction in instructions) {
      final accounts = instruction['accounts'] as List;
      for (final account in accounts) {
        final pubkey = account['pubkey'] as Uint8List;
        if (!_containsAccount(accountKeys, pubkey)) {
          accountKeys.add(pubkey);
          accountMeta.add({
            'isSigner': account['isSigner'] as bool,
            'isWritable': account['isWritable'] as bool,
          });
        }
      }
      
      // Program ID
      final programId = instruction['programId'] as Uint8List;
      if (!_containsAccount(accountKeys, programId)) {
        accountKeys.add(programId);
        accountMeta.add({'isSigner': false, 'isWritable': false});
      }
    }
    
    // Compact array length
    message.add(accountKeys.length);
    
    // Account keys
    for (final key in accountKeys) {
      message.addAll(key);
    }
    
    // Recent blockhash
    message.addAll(recentBlockhash);
    
    // Instructions
    message.add(instructions.length);
    
    for (final instruction in instructions) {
      // Program ID index
      final programId = instruction['programId'] as Uint8List;
      final programIdIndex = _findAccountIndex(accountKeys, programId);
      message.add(programIdIndex);
      
      // Accounts
      final accounts = instruction['accounts'] as List;
      message.add(accounts.length);
      for (final account in accounts) {
        final pubkey = account['pubkey'] as Uint8List;
        final accountIndex = _findAccountIndex(accountKeys, pubkey);
        message.add(accountIndex);
      }
      
      // Data
      final data = instruction['data'] as Uint8List;
      message.add(data.length);
      message.addAll(data);
    }
    
    return Uint8List.fromList(message);
  }
  
  // 계정이 이미 존재하는지 확인
  static bool _containsAccount(List<Uint8List> accounts, Uint8List target) {
    for (final account in accounts) {
      if (_areEqual(account, target)) {
        return true;
      }
    }
    return false;
  }
  
  // 계정 인덱스 찾기
  static int _findAccountIndex(List<Uint8List> accounts, Uint8List target) {
    for (int i = 0; i < accounts.length; i++) {
      if (_areEqual(accounts[i], target)) {
        return i;
      }
    }
    return -1;
  }
  
  // Uint8List 비교
  static bool _areEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  
  // Base58 디코딩 헬퍼
  static Uint8List _base58Decode(String encoded) {
    return SolanaWallet.decodeBase58(encoded);
  }
  
  // 트랜잭션에 서명 추가
  static Uint8List signTransaction(
    Uint8List transactionMessage,
    SolanaWallet wallet,
  ) {
    // 트랜잭션 메시지 해시
    final messageHash = sha256.convert(transactionMessage).bytes;
    
    // 서명 생성
    final signature = wallet.signTransaction(Uint8List.fromList(messageHash));
    
    // 서명된 트랜잭션 구성
    final signedTransaction = <int>[];
    
    // Compact array of signatures
    signedTransaction.add(1); // Number of signatures
    signedTransaction.addAll(signature);
    
    // Message
    signedTransaction.addAll(transactionMessage);
    
    return Uint8List.fromList(signedTransaction);
  }
  
  // 트랜잭션을 Base64로 인코딩 (RPC 전송용)
  static String encodeTransaction(Uint8List signedTransaction) {
    return base64Encode(signedTransaction);
  }
  
  // 트랜잭션 시뮬레이션 (실제 전송 전 확인)
  static Map<String, dynamic> simulateTransaction({
    required String fromAddress,
    required String toAddress,
    required double solAmount,
    required int currentBalance,
  }) {
    final lamports = solToLamports(solAmount);
    final estimatedFee = 5000; // 대략적인 트랜잭션 수수료 (5000 lamports)
    
    final result = <String, dynamic>{};
    
    // 잔액 검사
    if (currentBalance < (lamports + estimatedFee)) {
      result['success'] = false;
      result['error'] = '잔액이 부족합니다. 필요: ${lamportsToSol(lamports + estimatedFee)} SOL, 보유: ${lamportsToSol(currentBalance)} SOL';
      return result;
    }
    
    // 주소 유효성 검사
    try {
      _base58Decode(fromAddress);
      _base58Decode(toAddress);
    } catch (e) {
      result['success'] = false;
      result['error'] = '잘못된 주소 형식입니다.';
      return result;
    }
    
    // 자기 자신에게 전송하는지 확인
    if (fromAddress == toAddress) {
      result['success'] = false;
      result['error'] = '자기 자신에게는 전송할 수 없습니다.';
      return result;
    }
    
    result['success'] = true;
    result['estimatedFee'] = estimatedFee;
    result['totalCost'] = lamports + estimatedFee;
    result['remainingBalance'] = currentBalance - (lamports + estimatedFee);
    
    return result;
  }
}