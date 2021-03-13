use message_io::network::{NetEvent, Network, Transport};
use serde::{Deserialize, Serialize};
use std::{collections::HashSet, ffi::CStr, ffi::CString, thread, time::Duration};
use std::{os::raw::c_char, sync::mpsc};

#[derive(Serialize, Deserialize)]
pub enum Chunk {
    Data(Vec<u8>),
    Error,
    End,
}

#[derive(Serialize, Deserialize)]
pub enum NetMessage {
    HelloLan(String, u16),                   // user_name, server_port
    HelloUser(String),                       // user_name
    UserMessage(String),                     // content
    UserData(String, Chunk),                 // file_name, chunk
    Stream(Option<(Vec<u8>, usize, usize)>), // Option of (stream_data width, height ) None means stream has ended
}

impl NetMessage {
    fn ser(&self) -> Vec<u8> {
        bincode::serialize(self).unwrap()
    }
    fn deser(msg: Vec<u8>) -> Self {
        bincode::deserialize(&msg).unwrap()
    }
}

#[repr(C)]
#[derive(Debug)]
pub struct MessageFFi {
    tx: mpsc::Sender<UiMessage>,
    rx_recv: mpsc::Receiver<String>,
}

#[no_mangle]
pub extern "C" fn send_msg(message_ffi: *mut MessageFFi, msg: *mut c_char) {
    let message: &MessageFFi = unsafe { &*message_ffi };
    let msg = unsafe { CStr::from_ptr(msg) }.to_string_lossy().to_string();
    message.tx.send(UiMessage::Message(msg)).unwrap();
}

#[no_mangle]
pub extern "C" fn poll_recv_msg(message_ffi: *mut MessageFFi) -> *mut c_char {
    let message: &MessageFFi = unsafe { &*message_ffi };
    if let Ok(msg) = message.rx_recv.try_recv() {
        CString::new(msg).unwrap().into_raw()
    } else {
        CString::new("".to_string()).unwrap().into_raw()
    }
}

#[no_mangle]
pub extern "C" fn message_init(my_name: *mut c_char) -> *mut MessageFFi {
    let my_name = unsafe { CStr::from_ptr(my_name) };
    let my_name = my_name.to_string_lossy().to_string();

    let (mut network, mut events) = Network::split();
    let udp_addr = "238.255.0.1:5877";

    //listen tcp
    let (_, server_addr) = network.listen(Transport::Tcp, "0.0.0.0:0").unwrap();

    //listen udp
    network.listen(Transport::Udp, udp_addr).unwrap();

    //connect udp
    let udp_conn = network.connect(Transport::Udp, udp_addr).unwrap();

    //send helloudp
    network.send(
        udp_conn.0,
        &NetMessage::HelloLan(my_name.clone(), server_addr.port()).ser(),
    );

    let my_tcp_addr = format!("{}:{}", udp_conn.1.ip(), server_addr.port());
    dbg!(my_tcp_addr);

    let (tx, rx) = mpsc::channel::<UiMessage>();
    let (tx_recv, rx_recv) = mpsc::channel();

    thread::spawn(move || {
        let mut peers = HashSet::new();
        loop {
            std::thread::sleep(Duration::from_millis(100));
            if let Ok(msg) = rx.try_recv() {
                match msg {
                    UiMessage::AddPeer(peer) => {
                        let (peer_endpoint, _) = network.connect(Transport::Tcp, peer).unwrap();
                        // send hellotcp
                        network.send(peer_endpoint, &NetMessage::HelloUser(my_name.clone()).ser());
                        peers.insert(peer_endpoint);
                    }
                    UiMessage::Message(msg) => {
                        let msg = NetMessage::UserMessage(msg).ser();
                        for peer in peers.iter() {
                            network.send(*peer, &msg);
                        }
                    }
                }
            }
            if let Some(ev) = events.try_receive() {
                match ev {
                    NetEvent::Message(endpoint, message) => {
                        let message = NetMessage::deser(message);
                        match message {
                            NetMessage::HelloLan(_user_name, tcp_server_port) => {
                                if udp_conn.1 != endpoint.addr() {
                                    let peer_tcp_addr =
                                        format!("{}:{}", endpoint.addr().ip(), tcp_server_port);
                                    let (peer_endpoint, _) =
                                        network.connect(Transport::Tcp, peer_tcp_addr).unwrap();
                                    // send hellotcp
                                    network.send(
                                        peer_endpoint,
                                        &NetMessage::HelloUser(my_name.clone()).ser(),
                                    );

                                    peers.insert(peer_endpoint);
                                }
                            }
                            NetMessage::HelloUser(_name) => {
                                peers.insert(endpoint);
                            }
                            NetMessage::UserMessage(data) => {
                                dbg!(&endpoint, &peers);
                                if peers.contains(&endpoint) {
                                    dbg!(&data);
                                    tx_recv.send(data).unwrap();
                                }
                            }
                            NetMessage::UserData(_, _) => {}
                            NetMessage::Stream(_) => {}
                        }
                    }
                    NetEvent::Connected(_x) => {}
                    NetEvent::Disconnected(_y) => {}
                }
            }
        }
    });

    Box::into_raw(Box::new(MessageFFi { tx, rx_recv }))
}

enum UiMessage {
    AddPeer(String),
    Message(String),
}

#[no_mangle]
pub unsafe extern "C" fn add_peer(message_ffi: *mut MessageFFi, peer: *mut c_char) {
    let message_ffi = &*message_ffi;
    let peer = CStr::from_ptr(peer).to_string_lossy().to_string();

    message_ffi.tx.send(UiMessage::AddPeer(peer)).unwrap();
}

#[test]
fn t() {
    let m = message_init(CString::new("qaze").unwrap().into_raw());
    let mut input = String::new();
    let stdin = std::io::stdin();
    loop {
        stdin.read_line(&mut input).unwrap();
        if input.starts_with("a") {
            unsafe {
                add_peer(
                    m,
                    CString::new(input.trim()[1..].to_owned())
                        .unwrap()
                        .into_raw(),
                );
            }
        } else {
            send_msg(m, CString::new(input.clone()).unwrap().into_raw());
        }
        input.clear();
    }
}
