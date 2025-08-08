import 'dart:convert';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import '../models/wallet_model.dart';

class PhantomWalletService {
  String? _connectedAddress;
  bool _isConnected = false;
  
  // App 정보
  static const String _appName = 'Solana Mobile Wallet';
  static const String _redirectUrl = 'https://phantom.app';
  
  PhantomWalletService();
  
  // Phantom 지갑 연결 요청 (딥링크 방식)
  Future<Map<String, dynamic>> connectWallet() async {
    try {
      // 연결 요청용 nonce 생성
      final nonce = _generateNonce();
      
      // Phantom 딥링크 URL 생성
      final phantomUrl = Uri(
        scheme: 'phantom',
        host: 'v1',
        path: '/connect',
        queryParameters: {
          'app_url': _redirectUrl,
          'dapp_name': _appName,
          'nonce': nonce,
          'redirect_link': _redirectUrl,
        },
      );
      
      // Phantom 앱 실행
      final launched = await launchUrl(phantomUrl, mode: LaunchMode.externalApplication);
      
      if (!launched) {
        // Phantom 앱이 설치되지 않은 경우 Play Store로 이동
        final playStoreUrl = Uri.parse('https://play.google.com/store/apps/details?id=app.phantom');
        await launchUrl(playStoreUrl, mode: LaunchMode.externalApplication);
        throw Exception('Phantom 지갑이 설치되지 않았습니다. 설치 후 다시 시도해주세요.');
      }
      
      // 실제 연결은 딥링크 콜백에서 처리
      // 여기서는 연결 요청만 수행
      return {
        'status': 'connecting',
        'message': 'Phantom 지갑에서 연결을 승인해주세요.',
        'nonce': nonce,
      };
    } catch (e) {
      throw Exception('Phantom 지갑 연결 실패: $e');
    }
  }
  
  // 지갑 연결 상태 설정 (딥링크 콜백에서 호출)
  void setConnectedWallet(String address) {
    _connectedAddress = address;
    _isConnected = true;
  }
  
  // 지갑 연결 해제
  Future<void> disconnectWallet() async {
    _connectedAddress = null;
    _isConnected = false;
  }
  
  // 지갑 연결 상태 확인
  bool isWalletConnected() {
    return _isConnected && _connectedAddress != null;
  }
  
  // 연결된 지갑 주소 가져오기
  String? getConnectedWalletAddress() {
    return _connectedAddress;
  }
  
  // 연결된 지갑 정보 가져오기
  Map<String, dynamic>? getWalletInfo() {
    if (!isWalletConnected()) return null;
    
    return {
      'address': _connectedAddress,
      'label': 'Phantom Wallet',
      'connected': _isConnected,
    };
  }
  
  // 트랜잭션 서명 및 전송 (딥링크 방식)
  Future<Map<String, dynamic>> signAndSendTransaction(String transaction) async {
    if (!isWalletConnected()) {
      throw Exception('Phantom 지갑이 연결되지 않았습니다.');
    }
    
    try {
      // 트랜잭션 서명용 nonce 생성
      final nonce = _generateNonce();
      
      // Phantom 딥링크 URL 생성
      final phantomUrl = Uri(
        scheme: 'phantom',
        host: 'v1',
        path: '/signAndSendTransaction',
        queryParameters: {
          'dapp_name': _appName,
          'nonce': nonce,
          'redirect_link': _redirectUrl,
          'transaction': transaction,
        },
      );
      
      // Phantom 앱에서 트랜잭션 승인 요청
      final launched = await launchUrl(phantomUrl, mode: LaunchMode.externalApplication);
      
      if (!launched) {
        throw Exception('Phantom 앱을 실행할 수 없습니다.');
      }
      
      return {
        'status': 'pending',
        'message': 'Phantom 지갑에서 트랜잭션을 승인해주세요.',
        'nonce': nonce,
      };
    } catch (e) {
      throw Exception('트랜잭션 서명 요청 실패: $e');
    }
  }
  
  // 메시지 서명 (딥링크 방식)
  Future<Map<String, dynamic>> signMessage(String message) async {
    if (!isWalletConnected()) {
      throw Exception('Phantom 지갑이 연결되지 않았습니다.');
    }
    
    try {
      final nonce = _generateNonce();
      final encodedMessage = base64Encode(utf8.encode(message));
      
      final phantomUrl = Uri(
        scheme: 'phantom',
        host: 'v1',
        path: '/signMessage',
        queryParameters: {
          'dapp_name': _appName,
          'nonce': nonce,
          'redirect_link': _redirectUrl,
          'message': encodedMessage,
        },
      );
      
      final launched = await launchUrl(phantomUrl, mode: LaunchMode.externalApplication);
      
      if (!launched) {
        throw Exception('Phantom 앱을 실행할 수 없습니다.');
      }
      
      return {
        'status': 'pending',
        'message': 'Phantom 지갑에서 메시지 서명을 승인해주세요.',
        'nonce': nonce,
      };
    } catch (e) {
      throw Exception('메시지 서명 요청 실패: $e');
    }
  }
  
  // Phantom 지갑이 설치되어 있는지 확인
  static Future<bool> isPhantomWalletInstalled() async {
    try {
      final phantomUrl = Uri.parse('phantom://');
      final canLaunch = await canLaunchUrl(phantomUrl);
      return canLaunch;
    } catch (e) {
      return false;
    }
  }
  
  // Phantom 지갑 설치 페이지로 이동
  static Future<void> openPhantomInstallPage() async {
    final playStoreUrl = Uri.parse('https://play.google.com/store/apps/details?id=app.phantom');
    await launchUrl(playStoreUrl, mode: LaunchMode.externalApplication);
  }
  
  // nonce 생성 (보안을 위한 랜덤 문자열)
  String _generateNonce() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }
}

// PhantomWallet 정보를 담는 간단한 클래스
class PhantomWallet {
  final String address;
  final String? label;
  final bool connected;
  
  PhantomWallet({
    required this.address,
    this.label,
    this.connected = true,
  });
  
  factory PhantomWallet.fromAddress(String address) {
    return PhantomWallet(
      address: address,
      label: 'Phantom Wallet',
      connected: true,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'label': label,
      'connected': connected,
    };
  }
  
  @override
  String toString() {
    return 'PhantomWallet(address: $address, label: $label, connected: $connected)';
  }
}