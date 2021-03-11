use message_io::network::{NetEvent, Network, Transport};
use std::{ffi::CStr, ffi::CString, thread, time::Duration};
use std::{os::raw::c_char, sync::mpsc};

#[repr(C)]
#[derive(Debug)]
pub struct MessageFFi {
    tx: mpsc::Sender<String>,
    rx_recv: mpsc::Receiver<String>,
}

#[no_mangle]
pub extern "C" fn send_msg(message_ffi: *mut MessageFFi, msg: *mut c_char) {
    let message: &MessageFFi = unsafe { &*message_ffi };
    let msg = unsafe { CStr::from_ptr(msg) }.to_string_lossy().to_string();
    message.tx.send(msg).unwrap();
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
    let _my_name = my_name.to_string_lossy().to_string();

    let (mut network, mut events) = Network::split();
    let udp_addr = "238.255.0.1:5877";

    //listen udp
    network.listen(Transport::Udp, udp_addr).unwrap();

    //connect udp
    let udp_conn = network.connect(Transport::Udp, udp_addr).unwrap();

    let (tx, rx) = mpsc::channel::<String>();
    let (tx_recv, rx_recv) = mpsc::channel();

    thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(1));
        if let Ok(msg) = rx.try_recv() {
            network.send(udp_conn.0, msg.as_bytes());
        }
        if let Some(ev) = events.try_receive() {
            match ev {
                NetEvent::Message(endpoint, data) => {
                    let message = String::from_utf8(data).unwrap();
                    // check if its not our msg
                    if udp_conn.1 != endpoint.addr() {
                        dbg!(&message);
                        tx_recv.send(message).unwrap();
                    }
                }
                NetEvent::Connected(_x) => {}
                NetEvent::Disconnected(_y) => {}
            }
        }
    });

    Box::into_raw(Box::new(MessageFFi { tx, rx_recv }))
}

#[test]
fn t() {
    let m = message_init(CString::new("qaze").unwrap().into_raw());
    let mut input = String::new();
    let stdin = std::io::stdin();
    loop {
        stdin.read_line(&mut input).unwrap();
        send_msg(m, CString::new(input.clone()).unwrap().into_raw());
        input.clear();
    }
}
