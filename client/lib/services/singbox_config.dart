import 'dart:convert';

/// Builds a full sing-box JSON configuration from a VLESS share link.
///
/// The backend hands out VLESS REALITY links like:
///   `vless://UUID@IP:PORT?security=reality&sni=SNI&fp=chrome`
///   `&pbk=PUBLICKEY&sid=SHORTID&flow=xtls-rprx-vision&type=tcp#NAME`
///
/// The `sing_box` plugin passes the config verbatim to libbox, so we must emit a
/// complete config (tun inbound + dns + route + outbound), not just the outbound.
class SingBoxConfig {
  /// Parses [vlessLink] and returns a pretty-printed sing-box config JSON string.
  /// Throws [FormatException] if the link is not a valid VLESS link.
  static String fromVlessLink(String vlessLink) {
    final uri = Uri.parse(vlessLink.trim());
    if (uri.scheme != 'vless') {
      throw const FormatException('Not a VLESS link');
    }

    final uuid = Uri.decodeComponent(uri.userInfo);
    final server = uri.host;
    final port = uri.port;
    final q = uri.queryParameters;

    if (uuid.isEmpty || server.isEmpty || port == 0) {
      throw const FormatException('VLESS link missing uuid/host/port');
    }

    final security = q['security'] ?? 'none';
    final sni = q['sni'] ?? q['peer'] ?? '';
    final fingerprint = q['fp'] ?? 'chrome';
    final publicKey = q['pbk'] ?? '';
    final shortId = q['sid'] ?? '';
    final flow = q['flow'] ?? '';

    final Map<String, dynamic> outbound = {
      'type': 'vless',
      'tag': 'proxy',
      'server': server,
      'server_port': port,
      'uuid': uuid,
      'packet_encoding': 'xudp',
    };
    if (flow.isNotEmpty) {
      outbound['flow'] = flow;
    }

    if (security == 'reality' || security == 'tls') {
      final tls = <String, dynamic>{
        'enabled': true,
        'server_name': sni,
        'utls': {'enabled': true, 'fingerprint': fingerprint},
      };
      if (security == 'reality') {
        tls['reality'] = {
          'enabled': true,
          'public_key': publicKey,
          'short_id': shortId,
        };
      }
      outbound['tls'] = tls;
    }

    // NOTE: This targets the sing-box 1.12+/1.13 schema (the vendored Libbox is
    // sing-box 1.13.x). Compared to older configs:
    //  - the `dns` outbound was REMOVED in 1.13 -> DNS is hijacked via a route
    //    action (`hijack-dns`) instead of routed to a `dns-out` outbound;
    //  - DNS servers use the typed format (`type` + `server`) instead of the
    //    legacy `address` string;
    //  - sniffing is a route action instead of an inbound flag;
    //  - outbound server domains are resolved via `default_domain_resolver`.
    final config = <String, dynamic>{
      'log': {'level': 'warn', 'timestamp': true},
      'dns': {
        'servers': [
          {
            'tag': 'proxy-dns',
            'type': 'tls',
            'server': '1.1.1.1',
            'detour': 'proxy',
          },
          {
            // No `detour` here: in sing-box 1.13 pointing a DNS server's detour
            // at a plain (empty) `direct` outbound is rejected. Local DNS is
            // resolved through the default (direct) path automatically.
            'tag': 'local-dns',
            'type': 'udp',
            'server': '223.5.5.5',
          },
        ],
        'final': 'proxy-dns',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.18.0.1/30', 'fdfe:dcba:9876::1/126'],
          'mtu': 9000,
          'auto_route': true,
          'strict_route': true,
          'stack': 'gvisor',
        },
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': [
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
          {'ip_is_private': true, 'outbound': 'direct'},
        ],
        'final': 'proxy',
        'auto_detect_interface': true,
        'default_domain_resolver': 'local-dns',
      },
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }
}
