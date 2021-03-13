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

// linux
final path = './librust_lib.so';
// android
final andro_path = 'librust_andro_lib.so';

final dylib = DynamicLibrary.open((Platform.isLinux)
    ? path
    : (Platform.isAndroid)
        ? andro_path
        : throw "Add specific platform lib here");

final message_init = dylib
    .lookup<NativeFunction<message_init_type>>('message_init')
    .asFunction<message_init_type>();
final send_msg = dylib
    .lookup<NativeFunction<send_msg_native>>('send_msg')
    .asFunction<send_msg_dart>();
final poll_recv_msg = dylib
    .lookup<NativeFunction<poll_recv_msg_type>>('poll_recv_msg')
    .asFunction<poll_recv_msg_type>();

final add_peer = dylib
    .lookup<NativeFunction<send_msg_native>>('add_peer')
    .asFunction<send_msg_dart>();

final get_my_tcp_addr = dylib
    .lookup<NativeFunction<poll_recv_msg_type>>('get_my_tcp_addr')
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
            drawer: Drawer(
                child: ListView(children: [
              DrawerHeader(
                child: Text('Drawer Header'),
                decoration: BoxDecoration(
                  color: Colors.blue,
                ),
              ),
              AddIp(),
              MyIp(),
            ]))));
  }
}

class MyIp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
        title: Text("My Ip adress"),
        onTap: () {
          //logic here
          Navigator.push(context, MaterialPageRoute<void>(
            builder: (BuildContext context) {
              return Scaffold(
                  appBar: AppBar(title: Text('My Ip adress')),
                  body: Center(child: Text(get_my_tcp_addr(message_ffi).toDartString())));
            },
          ));
        });
  }
}

class AddIp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
        title: Text("Add ip adress"),
        onTap: () {
          //logic here
          Navigator.push(context, MaterialPageRoute<void>(
            builder: (BuildContext context) {
              return Scaffold(
                  appBar: AppBar(title: Text('Add ip adress')),
                  body: Center(
                      child: Column(children: [
                    TextField(
                      decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '192.168.1.2:62555'),
                      onSubmitted: (peer) {
                        add_peer(message_ffi, peer.toNativeUtf8());
                        Navigator.pop(context);
                      },
                    ),
                  ])));
            },
          ));
        });
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
