import 'dart:ffi';
import 'dart:io' show Platform, sleep;
import 'package:flutter/material.dart';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'dart:async';

class MessageFFi extends Struct {
  Pointer<Void> _phantomData;
}

typedef message_init_type = MessageFFi Function(Pointer<Utf8> name);
typedef poll_recv_msg_type = Pointer<Utf8> Function(MessageFFi message);

typedef send_msg_native = Void Function(MessageFFi message, Pointer<Utf8> msg);
typedef send_msg_dart = void Function(MessageFFi message, Pointer<Utf8> msg);

void main() {
  var path = './librust_lib.so';
  if (Platform.isAndroid) path = 'librust_andro_lib.so';
  final dylib = DynamicLibrary.open(path);

  final message_init = dylib
      .lookup<NativeFunction<message_init_type>>('message_init')
      .asFunction<message_init_type>();

  final send_msg = dylib
      .lookup<NativeFunction<send_msg_native>>('send_msg')
      .asFunction<send_msg_dart>();

  final poll_recv_msg = dylib
      .lookup<NativeFunction<poll_recv_msg_type>>('poll_recv_msg')
      .asFunction<poll_recv_msg_type>();

  var message_ffi = message_init("User1".toNativeUtf8());

  runApp(MyApp(message_ffi, send_msg, poll_recv_msg));
}

class MyApp extends StatelessWidget {
  final MessageFFi message_ffi;
  final send_msg_dart send_msg;
  final poll_recv_msg_type poll_recv_msg;

  MyApp(this.message_ffi, this.send_msg, this.poll_recv_msg);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: "Chat",
        home: Scaffold(
          appBar: AppBar(
            title: Text("Chat"),
          ),
          body: Body(this.message_ffi, this.send_msg, this.poll_recv_msg),
        ));
  }
}

class Body extends StatefulWidget {
  final MessageFFi message_ffi;
  final send_msg_dart send_msg;
  final poll_recv_msg_type poll_recv_msg;

  Body(this.message_ffi, this.send_msg, this.poll_recv_msg);

  @override
  _BodyState createState() =>
      _BodyState(this.message_ffi, this.send_msg, this.poll_recv_msg);
}

class _BodyState extends State<Body> {
  final MessageFFi message_ffi;
  final send_msg_dart send_msg;
  final poll_recv_msg_type poll_recv_msg;

  final input_control = new TextEditingController();
  var chats = [];

  _BodyState(this.message_ffi, this.send_msg, this.poll_recv_msg);

  @override
  void initState() {
    super.initState();
    new Timer.periodic(Duration(seconds: 1), (Timer t) {
      final msg = this.poll_recv_msg(this.message_ffi).toDartString();
      if (msg != "") {
        setState(() {
          chats.add([1, msg]);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Expanded(
          child: ListView(
              children: this.chats.map((mc) {
        final mark = mc[0];
        final chat = mc[1];
        return Card(
            child: Text(chat),
            color: (mark == 0) ? Color(0xFF42A5F5) : Color(0x0a22b5f5));
      }).toList())),
      TextField(
          onSubmitted: (msg) {
            setState(() {
              this.chats.add([0, msg]);
            });
            this.send_msg(this.message_ffi, msg.toNativeUtf8());
            this.input_control.clear();
          },
          controller: input_control),
    ]);
  }
}
