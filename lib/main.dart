import 'dart:ffi';
import 'dart:io' show Platform, sleep;
import 'package:flutter/material.dart';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'dart:async';

////////////////
///////FFI//////
////////////////

class MessageFFi extends Struct {
  Pointer<Void>? _phantomData;
}

typedef message_init_type = MessageFFi Function(Pointer<Utf8> name);
typedef poll_recv_msg_type = Pointer<Utf8> Function(MessageFFi message);

typedef send_msg_native = Void Function(MessageFFi message, Pointer<Utf8> msg);
typedef send_msg_dart = void Function(MessageFFi message, Pointer<Utf8> msg);

final path = './librust_lib.so';
// android
//final path = 'librust_andro_lib.so';
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

final message_ffi = message_init("User1".toNativeUtf8());

///////////////
///////////////
///////////////

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: "Chat",
        home: Scaffold(
          appBar: AppBar(
            title: Text("Chat"),
          ),
          body: Body(),
        ));
  }
}

class Body extends StatefulWidget {
  @override
  _BodyState createState() => _BodyState();
}

class _BodyState extends State<Body> {
  final input_control = TextEditingController();
  final _scrollController = ScrollController();
  _scrollToBottom() {
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  var chats = [];

  @override
  void initState() {
    super.initState();
    new Timer.periodic(Duration(seconds: 1), (Timer t) {
      final msg = poll_recv_msg(message_ffi).toDartString();
      if (msg != "") {
        setState(() {
          this.chats.add([1, msg]);
          this._scrollToBottom();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Expanded(
          child: ListView(
              controller: _scrollController,
              children: this.chats.map((mc) {
                final mark = mc[0];
                final chat = mc[1];

				//card taken from https://github.com/Ekeminie/whatsapp_ui
                final card = ListTile(
                  leading: new CircleAvatar(
                    foregroundColor: Theme.of(context).primaryColor,
                    backgroundColor: Colors.grey,
                  ),
                  title: new Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      new Text(
                        (mark) == 0 ? "me" : "other",
                        style: new TextStyle(fontWeight: FontWeight.bold),
                      ),
                      new Text(
                        "time",
                        style:
                            new TextStyle(color: Colors.grey, fontSize: 14.0),
                      ),
                    ],
                  ),
                  subtitle: new Container(
                    padding: const EdgeInsets.only(top: 5.0),
                    child: new Text(
                      chat,
                      style: new TextStyle(color: Colors.blue, fontSize: 16.0),
                    ),
                  ),
                );
                return card;
              }).toList())),
      TextField(
          onSubmitted: (msg) {
            setState(() {
              this.chats.add([0, msg]);
            });
            send_msg(message_ffi, msg.toNativeUtf8());
            this.input_control.clear();
            this._scrollToBottom();
          },
          controller: input_control,
          decoration: InputDecoration(border: OutlineInputBorder())),
    ]);
  }
}
