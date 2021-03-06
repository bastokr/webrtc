import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_webrtc/web/rtc_session_description.dart';
//import 'package:flutter_webrtc/webrtc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:webrtc/src/loopback_sample.dart';
import 'dart:async';
import 'dart:core';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'dart:io';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'WebRTC lets learn together'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _offer = false;
  RTCPeerConnection _peerConnection;
  MediaStream _localStream;
  bool _inCalling = false;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  String mytoken;
  String targetServer = "https://www.toolsda.com/";

  String get sdpSemantics =>
      WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';
  final sdpController = TextEditingController();

  final String currentUserId = "";
  final FirebaseMessaging firebaseMessaging = FirebaseMessaging();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool isLoading = false;

  void registerNotification() {
    firebaseMessaging.requestNotificationPermissions();

    firebaseMessaging.configure(onMessage: (Map<String, dynamic> message) {
      print('onMessage: $message');
      Platform.isAndroid
          ? showNotification(message['notification'])
          : showNotification(message['aps']['alert']);
      return;
    }, onResume: (Map<String, dynamic> message) {
      print('onResume: $message');
      return;
    }, onLaunch: (Map<String, dynamic> message) {
      print('onLaunch: $message');
      return;
    });

    firebaseMessaging.getToken().then((token) {
      print('token: $token');

      mytoken = token;
      /*Firestore.instance
          .collection('users')
          .document(currentUserId)
          .updateData({'pushToken': token});
          */
    }).catchError((err) {
      //Fluttertoast.showToast(msg: err.message.toString());
    });
  }

  @override
  dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    sdpController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    configLocalNotification();
    registerNotification();
    super.initState();
    initRenderers();
    _makeCall();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  void _makeCall() async {
    _offer = false;

    final Map<String, dynamic> mediaConstraints = {
      'audio': false,
      'video': true
    };

    var configuration = <String, dynamic>{
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': sdpSemantics
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    if (_peerConnection != null) return;

    try {
      _peerConnection =
          await createPeerConnection(configuration, offerSdpConstraints);

      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);

      _localRenderer.srcObject = _localStream;

      switch (sdpSemantics) {
        case 'plan-b':
          await _peerConnection.addStream(_localStream);
          break;
        case 'unified-plan':
          _peerConnection.onTrack = _onTrack;
          _localStream.getTracks().forEach((track) {
            _peerConnection.addTrack(track, _localStream);
          });
          break;
      }
/*
      var description = await _peerConnection.createOffer(offerSdpConstraints);
      var sdp = description.sdp;
      print('sdp = $sdp');
      await _peerConnection.setLocalDescription(description);
      //change for loopback.
      description.type = 'answer';
      await _peerConnection.setRemojteDescription(description);




      
*/
      _peerConnection.onIceCandidate = (e) async {
        if (e.candidate != null) {
          print(json.encode({
            'candidate': e.candidate.toString(),
            'sdpMid': e.sdpMid.toString(),
            'sdpMlineIndex': e.sdpMlineIndex,
          }));
        }

        var sendData = {
          "chat_id": "test",
          "ontype": _offer ? "offer" : "answer",
          "candidate": {
            'candidate': e.candidate.toString(),
            'sdpMid': e.sdpMid.toString(),
            'sdpMlineIndex': e.sdpMlineIndex,
          }
        };

        print(sendData);
    if(!_offer){
        http.Response response =
            await http.post(Uri.parse(targetServer + 'CHAT_UPDATE'),
                headers: {
                  "Accept": "application/json",
                  "Content-Type": "application/x-www-form-urlencoded"
                },
                body: json.encode(sendData),
                encoding: Encoding.getByName("utf-8"));
        print(response.statusCode);
      };
      };
      _peerConnection.onIceConnectionState = (e) {
        print(e);
      };

      _peerConnection.onAddStream = (stream) {
        print('addStream: ' + stream.id);
        _remoteRenderer.srcObject = stream;
      };

      /* Unfied-Plan replaceTrack
      var stream = await MediaDevices.getDisplayMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      await transceiver.sender.replaceTrack(stream.getVideoTracks()[0]);
      // do re-negotiation ....
      */
    } catch (e) {
      print(e.toString());
    }
    if (!mounted) return;

    // _timer = Timer.periodic(Duration(seconds: 1), handleStatsReport);

    setState(() {
      _inCalling = true;
    });
  }

  void _hangUp() async {
    try {
      await _localStream.dispose();
      await _peerConnection.close();
      _peerConnection = null;
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    } catch (e) {
      print(e.toString());
    }
    setState(() {
      _inCalling = false;
    });
    //  _timer.cancel();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _createOffer() async {
   // _makeCall();
    _offer = true;
    RTCSessionDescription description =
        await _peerConnection.createOffer({'offerToReceiveVideo': 1});
    var session = parse(description.sdp);
    print(json.encode(session));

    var sendData = {"chat_id": "test", "mytoken": mytoken, "offer": session};

    print(sendData);

    http.Response response =
        await http.post(Uri.parse(targetServer + 'CHAT_UPDATE'),
            headers: {
              "Accept": "application/json",
              "Content-Type": "application/x-www-form-urlencoded"
            },
            body: json.encode(sendData),
            encoding: Encoding.getByName("utf-8"));
    print(response.statusCode);

    sdpController.text = json.encode(session);
    _peerConnection.setLocalDescription(description);
  }

  void _createAnswer() async {
    _setRemoteDescription(_createAnswerSend);
  }

  void _createAnswerSend() async {
    RTCSessionDescription description =
        await _peerConnection.createAnswer({'offerToReceiveVideo': 1});
    var session = parse(description.sdp);
    print(json.encode(session));
    sdpController.text = json.encode(session);
    var sendData = {"chat_id": "test", "answer": session};
    http.Response response =
        await http.post(Uri.parse(targetServer + 'CHAT_UPDATE'),
            headers: {
              "Accept": "application/json",
              "Content-Type": "application/x-www-form-urlencoded"
            },
            body: json.encode(sendData),
            encoding: Encoding.getByName("utf-8"));
    print(response.statusCode);
    _peerConnection.setLocalDescription(description);
  }

  void _setRemoteDescription(_send) async {
    http.get(
      Uri.parse(targetServer + 'GET_CHAT/test'),
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded"
      },
    ).then((res) {
      if (res.statusCode == 200) {
        var list = jsonDecode(res.body) as List;
        String jsonString = _offer ? list[0]['answer'] : list[0]['offer'];
        sdpController.text = jsonString;

        dynamic session = jsonDecode('$jsonString');
        String sdp = write(session, null);
        // RTCSessionDescription description =
        //     new RTCSessionDescription(session['sdp'], session['type']);
        RTCSessionDescription description =
            new RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
        print(description.toMap());

        _peerConnection.setRemoteDescription(description);
        _send();
      }
    });
  }

  void _addCandidate() async {
    http.get(
      Uri.parse(targetServer + 'GET_CANDI/test'),
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded"
      },
    ).then((res) {
      if (res.statusCode == 200) {
        var list = jsonDecode(res.body) as List;

        for (int i = 0; i < list.length; i++) {
          String jsonString = list[i]['candidate'];
          sdpController.text = jsonString;
          dynamic session = jsonDecode('$jsonString');
          // String sdp = write(session, null);
          // RTCSessionDescription description =
          //     new RTCSessionDescription(session['sdp'], session['type']);
          //   String jsonString = sdpController.text;
          //dynamic session = await jsonDecode('$jsonString');
          //test
          print(session['candidate']);
          dynamic candidate = new RTCIceCandidate(
              session['candidate'],
              session['sdpMid'],
              int.parse(session['sdpMlineIndex'].toString()));
          _peerConnection.addCandidate(candidate);
        }
      }
    });
  }

  void _onTrack(RTCTrackEvent event) {
    print('onTrack');
    if (event.track.kind == 'video' && event.streams.isNotEmpty) {
      print('New stream: ' + event.streams[0].id);
      _remoteRenderer.srcObject = event.streams[0];
    }
  }

  SizedBox videoRenderers() => SizedBox(
      height: 210,
      child: Row(children: [
        Flexible(
          child: new Container(
            key: new Key("local"),
            margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
            decoration: new BoxDecoration(color: Colors.black),
            child: new RTCVideoView(_localRenderer, mirror: true),
          ),
        ),
        Flexible(
          child: new Container(
              key: new Key("remote"),
              margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: new BoxDecoration(color: Colors.black),
              child: new RTCVideoView(_remoteRenderer)),
        )
      ]));

  void empty() async {
    print("_setRemoteDescription");
  }

  void _setRemoteDescription2() async {
    _setRemoteDescription(empty);
  }

  Row offerAndAnswerButtons() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        new RaisedButton(
          // onPressed: () {
          //   return showDialog(
          //       context: context,
          //       builder: (context) {
          //         return AlertDialog(
          //           content: Text(sdpController.text),
          //         );
          //       });
          // },
          onPressed: _createOffer,
          child: Text('Offer'),
          color: Colors.amber,
        ),
        RaisedButton(
          onPressed: _createAnswer,
          child: Text('Answer'),
          color: Colors.amber,
        ),
      ]);

  Row sdpCandidateButtons() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        RaisedButton(
          onPressed: _setRemoteDescription2,
          child: Text('Set Remote Desc'),
          color: Colors.amber,
        ),
        RaisedButton(
          onPressed: _addCandidate,
          child: Text('Add Candidate'),
          color: Colors.amber,
        )
      ]);

  Padding sdpCandidatesTF() => Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: sdpController,
          keyboardType: TextInputType.multiline,
          maxLines: 4,
          maxLength: TextField.noMaxLength,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _inCalling ? _hangUp : _makeCall,
          tooltip: _inCalling ? 'Hangup' : 'Call',
          child: Icon(_inCalling ? Icons.call_end : Icons.phone),
        ),
        body: Container(
            child: Column(children: [
          videoRenderers(),
          offerAndAnswerButtons(),
          sdpCandidatesTF(),
          sdpCandidateButtons(),
          RaisedButton(
            child: Text('둥근 버튼'),
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (BuildContext context) => LoopBackSample()));
            },
            shape: RoundedRectangleBorder(
                borderRadius: new BorderRadius.circular(30.0)),
          )
        ])));
  }

  void configLocalNotification() {
    var initializationSettingsAndroid =
        new AndroidInitializationSettings('@mipmap/ic_launcher');

    var initializationSettingsIOS = new IOSInitializationSettings();
    var initializationSettings = new InitializationSettings(
        initializationSettingsAndroid, initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
    /*

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('app_icon');
final IOSInitializationSettings initializationSettingsIOS =
    IOSInitializationSettings(
        onDidReceiveLocalNotification: onDidReceiveLocalNotification);
final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS);
flutterLocalNotificationsPlugin.initialize(initializationSettings,
    onSelectNotification: onSelectNotification);

*/
  }

  Future onDidReceiveLocalNotification(
      int id, String title, String body, String payload) async {
    // display a dialog with the notification details, tap ok to go to another page
    showDialog(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text('Ok'),
            onPressed: () async {
              Navigator.of(context, rootNavigator: true).pop();
              /*
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SecondScreen(payload),
              ),
            );
            */
            },
          )
        ],
      ),
    );
  }

  void showNotification(message) async {
    var androidPlatformChannelSpecifics = new AndroidNotificationDetails(
      Platform.isAndroid ? 'com.srnote.webrtc' : 'com.srnote.webrtc',
      'Flutter chat demo',
      'your channel description',
      playSound: true,
      enableVibration: true,
      importance: Importance.Max,
      priority: Priority.High,
    );
    var iOSPlatformChannelSpecifics = new IOSNotificationDetails();
    var platformChannelSpecifics = new NotificationDetails(
        androidPlatformChannelSpecifics, iOSPlatformChannelSpecifics);

    print(message);
//    print(message['body'].toString());
//    print(json.encode(message));

    await flutterLocalNotificationsPlugin.show(0, message['title'].toString(),
        message['body'].toString(), platformChannelSpecifics,
        payload: json.encode(message));

//    await flutterLocalNotificationsPlugin.show(
//        0, 'plain title', 'plain body', platformChannelSpecifics,
//        payload: 'item x');
  }

  Future<bool> onBackPress() {
    // openDialog();
    return Future.value(false);
  }
}
