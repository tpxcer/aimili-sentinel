#!/usr/bin/env python3
from __future__ import annotations
import select
import socket
import threading
import urllib.parse
import time
from typing import Any

def parse_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0

def recv_exact(sock: socket.socket, size: int) -> bytes:
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("Unexpected disconnect.")
        data += chunk
    return data

def resolve_dns_over_tun0(host: str, dns_server: str = "8.8.8.8", timeout: float = 3.0) -> str | None:
    try:
        socket.inet_aton(host)
        return host
    except OSError:
        pass
    try:
        socket.inet_pton(socket.AF_INET6, host)
        return host
    except OSError:
        pass

    import random
    tx_id = random.getrandbits(16).to_bytes(2, "big")
    flags = b"\x01\x00"
    questions = b"\x00\x01"
    rrs = b"\x00\x00\x00\x00\x00\x00"

    qname = b""
    for part in host.split("."):
        if not part:
            continue
        part_bytes = part.encode("idna")
        qname += len(part_bytes).to_bytes(1, "big") + part_bytes
    qname += b"\x00"

    qtype_qclass = b"\x00\x01\x00\x01"
    packet = tx_id + flags + questions + rrs + qname + qtype_qclass

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.settimeout(timeout)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b"tun0")
        except OSError as e:
            if "operation not permitted" in str(e).lower() or e.errno == 1:
                print("[DNS 绑定失败] [错误代码 3006] DNS 解析绑定 tun0 权限不足，请确保程序以 root 权限运行！", flush=True)
            elif "no such device" in str(e).lower() or e.errno == 19:
                print("[DNS 绑定失败] [错误代码 3004] DNS 解析绑定 tun0 失败，网卡设备不存在，请检查 VPN 连接！", flush=True)
            return None
        sock.sendto(packet, (dns_server, 53))
        resp, _ = sock.recvfrom(2048)
    except Exception:
        return None
    finally:
        sock.close()

    if len(resp) < 12:
        return None
    if resp[:2] != tx_id:
        return None

    rcode = resp[3] & 0x0F
    if rcode != 0:
        return None

    offset = 12
    while offset < len(resp):
        length = resp[offset]
        if length == 0:
            offset += 1
            break
        elif (length & 0xC0) == 0xC0:
            offset += 2
            break
        else:
            offset += 1 + length

    offset += 4
    answers_count = int.from_bytes(resp[6:8], "big")
    if answers_count == 0:
        return None

    for _ in range(answers_count):
        if offset >= len(resp):
            break
        while offset < len(resp):
            length = resp[offset]
            if length == 0:
                offset += 1
                break
            elif (length & 0xC0) == 0xC0:
                offset += 2
                break
            else:
                offset += 1 + length
        if offset + 10 > len(resp):
            break
        atype = int.from_bytes(resp[offset : offset + 2], "big")
        aclass = int.from_bytes(resp[offset + 2 : offset + 4], "big")
        rdlength = int.from_bytes(resp[offset + 8 : offset + 10], "big")
        offset += 10
        if offset + rdlength > len(resp):
            break
        if atype == 1 and aclass == 1 and rdlength == 4:
            ip_bytes = resp[offset : offset + 4]
            return socket.inet_ntoa(ip_bytes)
        offset += rdlength
    return None

def create_connection(address: tuple[str, int], timeout: float = 20) -> socket.socket:
    host, port = address
    resolved_ip = resolve_dns_over_tun0(host)
    if resolved_ip:
        host = resolved_ip

    err = None
    for res in socket.getaddrinfo(host, port, 0, socket.SOCK_STREAM):
        af, socktype, proto, canonname, sa = res
        sock = None
        try:
            sock = socket.socket(af, socktype, proto)
            sock.settimeout(timeout)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b"tun0")
            sock.connect(sa)
            return sock
        except OSError as e:
            err = e
            if "operation not permitted" in str(e).lower() or e.errno == 1:
                err = OSError(f"[错误代码 3006] [ERR_PROXY_BIND_TUN_PERM_DENIED] 绑定虚拟网卡 tun0 失败，权限不足！必须以 root 权限运行，或者进程缺少 CAP_NET_RAW 权限。")
            elif "no such device" in str(e).lower() or e.errno == 19:
                err = OSError(f"[错误代码 3004] [ERR_ROUTE_DEV_NOT_FOUND] 绑定虚拟网卡 tun0 失败，找不到设备！这通常是因为 OpenVPN 核心未能成功连接或已被异常终止。")
            if sock is not None:
                sock.close()
    if err is not None:
        raise err
    else:
        raise OSError("getaddrinfo returns empty list")

def relay(left: socket.socket, right: socket.socket) -> None:
    sockets = [left, right]
    while True:
        readable, _, errored = select.select(sockets, [], sockets, 120)
        if errored:
            return
        for source in readable:
            target = right if source is left else left
            data = source.recv(65536)
            if not data:
                return
            target.sendall(data)

def socks5_client(client: socket.socket, first_byte: bytes) -> None:
    upstream = None
    try:
        methods_count = recv_exact(client, 1)[0]
        recv_exact(client, methods_count)
        client.sendall(b"\x05\x00")
        version, command, _, address_type = recv_exact(client, 4)
        if version != 5 or command != 1:
            client.sendall(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
            return
        if address_type == 1:
            host = socket.inet_ntoa(recv_exact(client, 4))
        elif address_type == 3:
            host = recv_exact(client, recv_exact(client, 1)[0]).decode("idna")
        elif address_type == 4:
            host = socket.inet_ntop(socket.AF_INET6, recv_exact(client, 16))
        else:
            client.sendall(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
            return
        port = int.from_bytes(recv_exact(client, 2), "big")
        try:
            upstream = create_connection((host, port), timeout=20)
        except Exception as e:
            print(f"[SOCKS5 代理失败] 目标 {host}:{port} 连接失败: {e}", flush=True)
            try:
                client.sendall(b"\x05\x04\x00\x01\x00\x00\x00\x00\x00\x00")
            except OSError:
                pass
            raise
        client.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
        relay(client, upstream)
    finally:
        client.close()
        if upstream:
            upstream.close()

def read_http_header(client: socket.socket, first_byte: bytes) -> bytes:
    data = first_byte
    while b"\r\n\r\n" not in data and len(data) < 65536:
        chunk = client.recv(4096)
        if not chunk:
            break
        data += chunk
    return data

def http_client(client: socket.socket, first_byte: bytes) -> None:
    upstream = None
    try:
        header = read_http_header(client, first_byte)
        head, rest = header.split(b"\r\n\r\n", 1)
        lines = head.decode("iso-8859-1", errors="replace").split("\r\n")
        method, target, version = lines[0].split(" ", 2)
        if method.upper() == "CONNECT":
            host, _, port_text = target.partition(":")
            port = parse_int(port_text) or 443
            upstream = create_connection((host, port), timeout=20)
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            if rest:
                upstream.sendall(rest)
            relay(client, upstream)
            return

        parsed = urllib.parse.urlsplit(target)
        if not parsed.hostname:
            client.sendall(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
            return
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        path = urllib.parse.urlunsplit(("", "", parsed.path or "/", parsed.query, ""))
        headers = [line for line in lines[1:] if not line.lower().startswith(("proxy-connection:", "connection:"))]
        request = f"{method} {path} {version}\r\n" + "\r\n".join(headers) + "\r\nConnection: close\r\n\r\n"
        upstream = create_connection((parsed.hostname, port), timeout=20)
        upstream.sendall(request.encode("iso-8859-1") + rest)
        relay(client, upstream)
    except Exception as e:
        print(f"[HTTP 代理失败] 代理请求目标连接失败: {e}", flush=True)
        try:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
        except OSError:
            pass
    finally:
        client.close()
        if upstream:
            upstream.close()

def proxy_client(client: socket.socket, address: tuple[str, int]) -> None:
    try:
        client.settimeout(30)
        first = recv_exact(client, 1)
        if first == b"\x05":
            socks5_client(client, first)
        else:
            http_client(client, first)
    except Exception as e:
        err_msg = str(e)
        if "[错误代码" in err_msg:
            print(f"[代理客户端连接失败] 客户端 {address} 遭遇系统性阻碍: {err_msg}", flush=True)
        try:
            client.close()
        except OSError:
            pass

def start_proxy_server(host: str, port: int) -> None:
    is_ipv6 = ":" in host or host == ""
    af = socket.AF_INET6 if is_ipv6 else socket.AF_INET
    try:
        server = socket.socket(af, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if is_ipv6:
            try:
                server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except OSError:
                pass
        server.bind((host, port))
        server.listen(256)
        print(f"HTTP/SOCKS5 proxy listening on {host}:{port}", flush=True)
    except Exception as e:
        if is_ipv6 and host == "::":
            print(f"[警告] 绑定 IPv6 {host}:{port} 失败 ({e})，正在尝试回退至 IPv4 0.0.0.0 ...", flush=True)
            try:
                server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("0.0.0.0", port))
                server.listen(256)
                print(f"HTTP/SOCKS5 proxy listening on 0.0.0.0:{port} (仅 IPv4)", flush=True)
            except Exception as ex:
                import vpn_utils
                diag = vpn_utils.diagnose_local_obstructions(port, host="0.0.0.0")
                diag_msg = diag[1] if diag else str(ex)
                print(f"[ERROR] Failed to start HTTP/SOCKS5 proxy on 0.0.0.0:{port}: {diag_msg}", flush=True)
                return
        elif is_ipv6 and host == "::1":
            print(f"[警告] 绑定 IPv6 {host}:{port} 失败 ({e})，正在尝试回退至 IPv4 127.0.0.1 ...", flush=True)
            try:
                server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", port))
                server.listen(256)
                print(f"HTTP/SOCKS5 proxy listening on 127.0.0.1:{port} (仅 IPv4)", flush=True)
            except Exception as ex:
                import vpn_utils
                diag = vpn_utils.diagnose_local_obstructions(port, host="127.0.0.1")
                diag_msg = diag[1] if diag else str(ex)
                print(f"[ERROR] Failed to start HTTP/SOCKS5 proxy on 127.0.0.1:{port}: {diag_msg}", flush=True)
                return
        else:
            import vpn_utils
            diag = vpn_utils.diagnose_local_obstructions(port, host=host)
            diag_msg = diag[1] if diag else str(e)
            print(f"[ERROR] Failed to start HTTP/SOCKS5 proxy on {host}:{port}: {diag_msg}", flush=True)
            return

    while True:
        try:
            client, address = server.accept()
            threading.Thread(target=proxy_client, args=(client, address), daemon=True).start()
        except Exception as e:
            print(f"[ERROR] Proxy accept failed: {e}", flush=True)
            time.sleep(0.5)