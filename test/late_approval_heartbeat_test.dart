import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/state/auth_service.dart';
import 'package:waha_kiosk/services/heartbeat_service.dart';
import 'package:waha_kiosk/services/late_approval_service.dart';

void main() {
  group('heartbeat_minutes', () {
    test('missing or unusable means off', () {
      expect(HeartbeatService.parseMinutes(null), 0);
      expect(HeartbeatService.parseMinutes(''), 0);
      expect(HeartbeatService.parseMinutes('abc'), 0);
      expect(HeartbeatService.parseMinutes('-5'), 0);
      expect(HeartbeatService.parseMinutes('0'), 0);
    });
    test('valid values are kept, capped at 1440', () {
      expect(HeartbeatService.parseMinutes('5'), 5);
      expect(HeartbeatService.parseMinutes(' 30 '), 30);
      expect(HeartbeatService.parseMinutes('99999'), 1440);
    });
  });

  group('late approval entry', () {
    test('survives being stored and read back', () {
      final e = LateApproval(
          orderId: 'o1', amount: 13.06, rrn: '627812555793', approvalCode: '217757', terminalId: '6499080464990804');
      final back = LateApproval.tryParse(_json(e.withAttempt()));
      expect(back?.orderId, 'o1');
      expect(back?.amount, 13.06);
      expect(back?.rrn, '627812555793');
      expect(back?.attempts, 1);
    });
    test('an entry without an rrn is dropped', () {
      expect(LateApproval.tryParse('{"orderId":"o1","amount":1.0}'), isNull);
      expect(LateApproval.tryParse('not json'), isNull);
    });
  });

  group('late approval sending', () {
    test('a report saved while another is being sent is not lost', () async {
      SharedPreferences.setMockInitialValues({});
      await LocalPrefs.init();
      authService.token = 'tok';
      final gate = Completer<void>();
      var calls = 0;
      final client = MockClient((req) async {
        if (calls++ == 0) await gate.future; // hold the first send
        return http.Response('{"result":"PAID"}', 200);
      });
      final api = ApiClient(httpClient: client, baseUrl: 'http://test');
      final service = LateApprovalService.instance..start(api);

      final first = service.report(orderId: 'o1', amount: 1.0, rrn: 'rrn1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await service.report(orderId: 'o2', amount: 2.0, rrn: 'rrn2'); // arrives mid-send
      gate.complete();
      await first;

      final left = LocalPrefs.lateApprovals.map(LateApproval.tryParse).whereType<LateApproval>().map((e) => e.rrn).toList();
      expect(left, ['rrn2']);

      await service.flush(); // sends the second one and stops the timer
      expect(LocalPrefs.lateApprovals, isEmpty);
    });
  });
}

String _json(LateApproval e) {
  final m = e.toJson();
  return '{${m.entries.map((x) => '"${x.key}":${x.value is String ? '"${x.value}"' : x.value}').join(',')}}';
}
