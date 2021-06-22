use message_io::network::{Endpoint, Transport};
use message_io::node::{self, NodeTask, StoredNetEvent, StoredNodeEvent as NodeEvent};
use serde::{Deserialize, Serialize};
use std::{collections::HashSet, ffi::CStr, ffi::CString, thread, time::Duration};
use std::{os::raw::c_char, sync::mpsc};

// #[derive(Serialize, Deserialize)]
// pub enum Chunk {
//     Data(Vec<u8>),
//     Error,
//     End,
// }

#[derive(Serialize, Deserialize)]
pub enum NetMessage {
    HelloLan(String, u16),                   // user_name, server_port
    HelloUser(String),                       // user_name
    UserMessage(String),                     // content
    UserData(String, Vec<u8>),               // file_name, chunk
    Stream(Option<(Vec<u8>, usize, usize)>), // Option of (stream_data width, height ) None means stream has ended
}

impl NetMessage {
    fn ser(&self) -> Vec<u8> {
        bincode::serialize(self).unwrap()
    }
    fn deser(msg: &[u8]) -> Result<Self, Box<bincode::ErrorKind>> {
        bincode::deserialize(msg)
    }
}

#[repr(C)]
pub struct MessageFFi {
    tx: mpsc::Sender<UiMessage>,
    rx_recv: mpsc::Receiver<String>,
    my_tcp_addr: String,
    _task: NodeTask,
}

/// # Safety
/// Internal
#[no_mangle]
pub unsafe extern "C" fn send_msg(message_ffi: *mut MessageFFi, msg: *mut c_char) {
    let message: &MessageFFi = &*message_ffi;
    let msg = CStr::from_ptr(msg).to_string_lossy().to_string();
    message.tx.send(UiMessage::Message(msg)).unwrap();
}

/// # Safety
/// Internal
#[no_mangle]
pub unsafe extern "C" fn poll_recv_msg(message_ffi: *mut MessageFFi) -> *mut c_char {
    let message: &MessageFFi = &*message_ffi;
    if let Ok(msg) = message.rx_recv.try_recv() {
        CString::new(msg).unwrap().into_raw()
    } else {
        CString::new("".to_string()).unwrap().into_raw()
    }
}

/// # Safety
/// Internal
#[no_mangle]
pub unsafe extern "C" fn message_init(my_name: *mut c_char) -> *mut MessageFFi {
    let my_name = CStr::from_ptr(my_name);
    let my_name = my_name.to_string_lossy().to_string();

    let (handler, listener) = node::split::<NetMessage>();
    //NOTE: exchange performance for convieniences
    let (_task, mut receiver) = listener.enqueue();

    //listen tcp
    let (_, server_addr) = handler
        .network()
        .listen(Transport::FramedTcp, "0.0.0.0:0")
        .unwrap();

    let udp_addr = "239.255.0.1:5877";

    //listen udp
    handler.network().listen(Transport::Udp, udp_addr).unwrap();

    //connect udp
    let udp_conn = handler.network().connect(Transport::Udp, udp_addr).unwrap();

    let my_tcp_addr = format!("{}:{}", udp_conn.1.ip(), server_addr.port());
    dbg!(&my_tcp_addr);

    let (tx, rx) = mpsc::channel::<UiMessage>();
    let (tx_recv, rx_recv) = mpsc::channel();

    thread::spawn(move || {
        // peers: Endpoint,Name
        let mut peers: HashSet<(Endpoint, String)> = HashSet::new();

        loop {
            std::thread::sleep(Duration::from_millis(100));
            if let Ok(msg) = rx.try_recv() {
                match msg {
                    UiMessage::AddPeer(_name, new_peer) => {
                        let (_peer_endpoint, _) = handler
                            .network()
                            .connect(Transport::FramedTcp, new_peer)
                            .unwrap();
                        //  FIXME send hellotcp?
                        //  handler
                        //      .network()
                        //      .send(peer_endpoint, &NetMessage::HelloUser(my_name.clone()).ser());
                        //  peers.insert((peer_endpoint, name));
                    }
                    UiMessage::Message(msg) => {
                        let msg = NetMessage::UserMessage(msg).ser();
                        dbg!(&peers);
                        for peer in peers.iter() {
                            handler.network().send(peer.0, &msg);
                        }
                    }
                    UiMessage::Data(file_name, data) => {
                        let msg = NetMessage::UserData(file_name, data).ser();
                        for peer in peers.iter() {
                            handler.network().send(peer.0, &msg);
                        }
                    }
                }
            }
            if let Some(NodeEvent::Network(ev)) = receiver.try_receive() {
                match ev {
                    StoredNetEvent::Message(endpoint, message) => {
                        let message = {
                            match NetMessage::deser(&message) {
                                Ok(data) => data,
                                Err(_) => continue,
                            }
                        };
                        match message {
                            NetMessage::HelloLan(user_name, tcp_server_port) => {
                                dbg!(&user_name);
                                if udp_conn.1 != endpoint.addr() {
                                    let peer_tcp_addr =
                                        format!("{}:{}", endpoint.addr().ip(), tcp_server_port);
                                    let (peer_endpoint, _) = handler
                                        .network()
                                        .connect(Transport::FramedTcp, peer_tcp_addr)
                                        .unwrap();

                                    peers.insert((peer_endpoint, user_name));
                                }
                            }
                            NetMessage::HelloUser(name) => {
                                dbg!(&name);
                                peers.insert((endpoint, name));
                            }
                            NetMessage::UserMessage(data) => {
                                dbg!(&endpoint, &peers);
                                if let Some(peer) = peers.iter().find(|peer| peer.0 == endpoint) {
                                    dbg!(&data);
                                    tx_recv.send(peer.1.clone() + ";" + &data).unwrap();
                                }
                            }
                            NetMessage::UserData(file_name, data) => {
                                let path = std::env::temp_dir().join(file_name);
                                dbg!(&path);
                                std::fs::write(&path, data).unwrap();
                            }
                            NetMessage::Stream(_) => {}
                        }
                    }
                    StoredNetEvent::Connected(x, _flag) => {
                        dbg!(&x);
                        if x == udp_conn.0 {
                            // We connected to the udp multicast group
                            // Send helloudp
                            dbg!(handler.network().send(
                                udp_conn.0,
                                &NetMessage::HelloLan(my_name.clone(), server_addr.port()).ser(),
                            ));
                        }
                        // Hello Tcp FIXME
                        else {
                            // send hellotcp
                            dbg!(handler
                                .network()
                                .send(x, &NetMessage::HelloUser(my_name.clone()).ser()));
                        }
                    }
                    StoredNetEvent::Disconnected(_y) => {}
                    StoredNetEvent::Accepted(_, _) => {}
                }
            }
        }
    });

    Box::into_raw(Box::new(MessageFFi {
        tx,
        rx_recv,
        my_tcp_addr,
        _task,
    }))
}

enum UiMessage {
    AddPeer(String, String),
    Message(String),
    Data(String, Vec<u8>),
}

/// # Safety
/// Internal
#[no_mangle]
pub unsafe extern "C" fn add_peer(message_ffi: *mut MessageFFi, peer: *mut c_char) {
    let message_ffi = &*message_ffi;
    let peer = CStr::from_ptr(peer).to_string_lossy().to_string();

    let mut peer = peer.split(';');
    let name = peer.next().unwrap();
    let addr = peer.next().unwrap();

    message_ffi
        .tx
        .send(UiMessage::AddPeer(name.into(), addr.into()))
        .unwrap();
}

/// # Safety
/// Internal
#[no_mangle]
pub unsafe extern "C" fn get_my_tcp_addr(message_ffi: *mut MessageFFi) -> *mut c_char {
    let message_ffi = &*message_ffi;
    CString::new(message_ffi.my_tcp_addr.clone())
        .unwrap()
        .into_raw()
}

/// # Safety
/// Internal
#[no_mangle]
pub unsafe extern "C" fn send_file(message_ffi: *mut MessageFFi, file_path: *mut c_char) {
    let message_ffi = &*message_ffi;
    let file_path = CStr::from_ptr(file_path).to_string_lossy().to_string();
    let file_name = std::path::Path::new(&file_path)
        .file_name()
        .unwrap()
        .to_str()
        .unwrap()
        .to_owned();
    let data = std::fs::read(file_path).unwrap();
    message_ffi
        .tx
        .send(UiMessage::Data(file_name, data))
        .unwrap();
}

#[test]
fn t() {
    unsafe {
        let name = CString::new("aze").unwrap().into_raw();
        let m = message_init(name);
        let mut input = String::new();
        let stdin = std::io::stdin();
        loop {
            stdin.read_line(&mut input).unwrap();
            if input.starts_with("a") {
                add_peer(
                    m,
                    CString::new(input.trim()[1..].to_owned())
                        .unwrap()
                        .into_raw(),
                );
            } else if input.starts_with("s") {
                let path = input.trim()[1..].to_owned();
                send_file(m, CString::new(path.clone()).unwrap().into_raw());
                let file_name = std::path::Path::new(&path)
                    .file_name()
                    .unwrap()
                    .to_str()
                    .unwrap()
                    .to_owned();
                send_msg(
                    m,
                    CString::new("file:///".to_string() + &file_name)
                        .unwrap()
                        .into_raw(),
                );
            } else {
                send_msg(m, CString::new(input.clone()).unwrap().into_raw());
            }
            input.clear();
        }
    }
}
