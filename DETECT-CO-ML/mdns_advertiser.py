"""Best-effort DNS-SD advertisement for the local DETECT-CO ML API."""

import ipaddress
import logging
import socket
import threading


SERVICE_TYPE = "_detectco-ml._tcp.local."
SERVICE_NAME = f"DETECT-CO ML.{SERVICE_TYPE}"
API_PORT = 8000
logger = logging.getLogger("detectco.ml.discovery")


def local_ipv4_addresses():
    """Find host IPv4 addresses without assuming a particular Wi-Fi subnet."""
    addresses = set()
    route_probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # A UDP connect selects the default route and sends no packet.
        route_probe.connect(("192.0.2.1", 9))
        addresses.add(route_probe.getsockname()[0])
    except OSError:
        pass
    finally:
        route_probe.close()

    try:
        for result in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(result[4][0])
    except OSError:
        pass

    return sorted(
        address
        for address in addresses
        if not ipaddress.ip_address(address).is_loopback
        and not ipaddress.ip_address(address).is_link_local
    )


class MlMdnsAdvertiser:
    def __init__(self):
        self._zeroconf = None
        self._service_info = None
        self._addresses = ()
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._watcher = None

    def start(self):
        from zeroconf import IPVersion, ServiceInfo, Zeroconf

        self._service_info_type = ServiceInfo
        self._zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
        self._refresh_addresses()
        self._watcher = threading.Thread(
            target=self._watch_network,
            name="detectco-mdns-address-watch",
            daemon=True,
        )
        self._watcher.start()
        return list(self._addresses)

    def _make_service_info(self, addresses):
        return self._service_info_type(
            SERVICE_TYPE,
            SERVICE_NAME,
            port=API_PORT,
            properties={"path": "/health", "version": "1"},
            server=f"{socket.gethostname()}.local.",
            parsed_addresses=addresses,
        )

    def _refresh_addresses(self):
        addresses = tuple(local_ipv4_addresses())
        with self._lock:
            if addresses == self._addresses:
                return
            zeroconf = self._zeroconf
            if zeroconf is None:
                return
            old_info = self._service_info
            new_info = self._make_service_info(addresses) if addresses else None
            if old_info is not None:
                zeroconf.unregister_service(old_info)
                self._service_info = None
                self._addresses = ()
            if new_info is not None:
                zeroconf.register_service(new_info)
            self._service_info = new_info
            self._addresses = addresses
            if addresses:
                logger.info("Advertising ML API at %s:%s", ", ".join(addresses), API_PORT)
            else:
                logger.info("Paused ML API mDNS advertisement; no LAN address is available")

    def _watch_network(self):
        while not self._stop_event.wait(5):
            try:
                self._refresh_addresses()
            except Exception:
                logger.warning("Could not refresh ML API mDNS address", exc_info=True)

    def stop(self):
        self._stop_event.set()
        if self._watcher is not None:
            self._watcher.join(timeout=2)
            self._watcher = None
        zeroconf = self._zeroconf
        if zeroconf is None:
            return
        with self._lock:
            try:
                if self._service_info is not None:
                    zeroconf.unregister_service(self._service_info)
            finally:
                self._service_info = None
                self._addresses = ()
                self._zeroconf = None
        try:
            zeroconf.close()
        finally:
            self._stop_event.clear()
