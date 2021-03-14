import 'dart:ffi';
import 'dart:io' show Platform, File;
import 'package:path/path.dart';
import 'dart:async';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

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
final send_file = dylib
    .lookup<NativeFunction<send_msg_native>>('send_file')
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

var clearFlag = ValueNotifier(false);

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
            floatingActionButton: Container(
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.red)),
                child: TextButton(
                  child: Text("Clear chat",
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.red)),
                  onPressed: () {
                    clearFlag.value = true;
                  },
                )),
            floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
            drawer: Drawer(
                child: ListView(children: [
              DrawerHeader(
                child: Icon(Icons.ac_unit_outlined, size: 42),
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
        title: Text("My Ip adress", style: TextStyle(fontSize: 22)),
        onTap: () {
          //logic here
          Navigator.push(context, MaterialPageRoute<void>(
            builder: (BuildContext context) {
              return Scaffold(
                  appBar: AppBar(title: Text('My Ip adress')),
                  body: Center(
                      child: Text(
                    get_my_tcp_addr(message_ffi).toDartString(),
                    style: TextStyle(fontSize: 30),
                  )));
            },
          ));
        });
  }
}

class AddIp extends StatelessWidget {
  final name_input = TextEditingController();
  final ip_input = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return ListTile(
        title: Text("Add ip adress", style: TextStyle(fontSize: 22)),
        onTap: () {
          //logic here
          Navigator.push(context, MaterialPageRoute<void>(
            builder: (BuildContext context) {
              return Scaffold(
                  appBar: AppBar(title: Text('Add ip adress')),
                  body: Center(
                      child: Column(children: [
                    Text("Peer name:", style: TextStyle(fontSize: 20)),
                    TextField(
                      controller: name_input,
                      decoration: InputDecoration(
                          border: OutlineInputBorder(), hintText: 'otherme'),
                    ),
                    Text("Ip:", style: TextStyle(fontSize: 20)),
                    TextField(
                      decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '192.168.1.2:62555'),
                      controller: ip_input,
                    ),
                    Divider(),
                    ElevatedButton(
                        child: Text("Ok"),
                        onPressed: () {
                          final peer =
                              this.name_input.text + ';' + this.ip_input.text;
                          add_peer(message_ffi, peer.toNativeUtf8());
                          Navigator.pop(context);
                        })
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
    _scrollController.animateTo(_scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
  }

  var chats = [];

  @override
  void initState() {
    super.initState();
    new Timer.periodic(Duration(milliseconds: 100), (Timer t) {
      final msg = poll_recv_msg(message_ffi).toDartString();
      if (msg != "") {
			  print(msg);
        setState(() {
          this.chats.add("${now()};$msg");
        });
        this._scrollToBottom();
      }
    });
    clearFlag.addListener(() {
      setState(() {
        this.chats.clear();
        clearFlag.value = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Expanded(
          child: ListView(
              controller: _scrollController,
              children: this.chats.map((mc) {
                final now = mc.split(';')[0];
                final user = mc.split(';')[1];
                final chat = mc.split(';')[2];

                final card = (user == "me")
                    ? ListTile(
                        leading: new CircleAvatar(
                            foregroundColor: Theme.of(context).primaryColor,
                            child: Text(user[0].toUpperCase())),
                        title: new Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            new Text(
                              user,
                              style: new TextStyle(fontWeight: FontWeight.bold),
                            ),
                            new Text(
                              now,
                              style: new TextStyle(
                                  color: Colors.grey, fontSize: 14.0),
                            ),
                          ],
                        ),
                        subtitle: new Container(
                          padding: const EdgeInsets.only(top: 5.0),
                          child: new Text(
                            chat,
                            style: new TextStyle(
                                color: Colors.blue, fontSize: 16.0),
                          ),
                        ),
                        onTap: () async {
                          if (chat.startsWith("file:///")) {
                            final tmpDir = await getTemporaryDirectory();
                            final chat_s = chat.split("file:///");
                            final path = chat_s[0] + tmpDir.path + chat_s[1];
                            print(path);
                            launch(path);
                          }
                        },
                      )
                    : ListTile(
                        trailing: new CircleAvatar(
                          foregroundColor: Theme.of(context).primaryColor,
                          child: Text(user[0].toUpperCase()),
                        ),
                        title: new Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            new Text(
                              now,
                              style: new TextStyle(
                                  color: Colors.grey, fontSize: 14.0),
                            ),
                            new Text(
                              user,
                              style: new TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        subtitle: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.only(top: 5.0),
                              child: new Text(
                                chat,
                                style: new TextStyle(
                                    color: Colors.blue, fontSize: 16.0),
                              ),
                            )),
                        onTap: () async {
                          if (chat.startsWith("file:///")) {
                            final tmpDir = await getTemporaryDirectory();
                            final chat_s = chat.split("file:///");
                            final path =
                                "file://" + tmpDir.path + "/" + chat_s[1];
                            launch(path);
                          }
                        },
                      );
                return card;
              }).toList())),
      TextField(
          onSubmitted: (msg) {
            setState(() {
              this.chats.add("${now()};me;$msg");
            });
            send_msg(message_ffi, msg.toNativeUtf8());
            this.input_control.clear();
            this._scrollToBottom();
          },
          controller: input_control,
          decoration: InputDecoration(
              border: OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () async {
                  var path;
                  if (Platform.isAndroid) {
                    final result = await FilePicker.platform.pickFiles();

                    if (result != null) {
                      path = result.files.single.path;
                    } else {
                      return;
                    }
                  } else {
                    final file = await openFile();
                    if (file != null) {
                      path = file.path;
                    } else {
                      return;
                    }
                  }
                  setState(() {
                    this.chats.add("${now()};me;$path");
                  });
                  String fileUri = "file:///" + basename(path);
				  //send msg needs to happen before send file!!
                  send_msg(message_ffi, "$fileUri".toNativeUtf8());
                  send_file(message_ffi, "$path".toNativeUtf8());

                  print("fileuri=$fileUri");
                },
                icon: Icon(Icons.send),
              ))),
    ]);
  }
}

// helpers
String now() {
  final date = DateTime.now();
  return "${date.year}-${date.month}-${date.day} ${date.hour}:${date.minute}";
}
