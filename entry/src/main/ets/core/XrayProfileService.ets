import { RoutingMode } from './AppPreferencesService';

interface XrayNode {
  name: string;
  server: string;
  port: number;
  uuid: string;
  flow: string;
  fingerprint: string;
  serverName: string;
  publicKey: string;
  shortId: string;
}

export class XrayProfileService {
  shouldTranslate(profile: string): boolean {
    return !/(?:^|[, {])type:\s*anytls(?:[, }]|$)/m.test(profile) &&
      this.extractRealityNodes(profile).length > 0;
  }

  supportedNodeNames(profile: string): string[] {
    return this.extractRealityNodes(profile).map((node: XrayNode) => node.name);
  }

  buildConfig(profile: string, preferredName: string, mode: RoutingMode): string {
    const nodes: XrayNode[] = this.extractRealityNodes(profile);
    if (nodes.length === 0) {
      throw new Error('订阅中没有可用的 VLESS Reality 节点');
    }
    let selected: XrayNode = nodes[0];
    for (let index: number = 0; index < nodes.length; index++) {
      if (nodes[index].name === preferredName) {
        selected = nodes[index];
        break;
      }
    }

    const quote = (value: string): string => JSON.stringify(value);
    const inbounds: string[] = ['{' +
      '"tag":"tun-in","protocol":"tun","listen":"127.0.0.1","port":0,"settings":{},' +
      '"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"metadataOnly":false}' +
    '}'];
    const outbounds: string[] = [];
    const routingRules: string[] = [];
    for (let index: number = 0; index < nodes.length; index++) {
      inbounds.push('{' +
        '"tag":"latency-' + index + '","protocol":"http","listen":"127.0.0.1",' +
        '"port":' + (17900 + index) + ',"settings":{}' +
      '}');
      routingRules.push('{' +
        '"type":"field","inboundTag":["latency-' + index + '"],"outboundTag":"node-' + index + '"' +
      '}');
    }
    const selectedIndex: number = nodes.indexOf(selected);
    const outboundOrder: number[] = [selectedIndex];
    for (let index: number = 0; index < nodes.length; index++) {
      if (index !== selectedIndex) {
        outboundOrder.push(index);
      }
    }
    for (let orderIndex: number = 0; orderIndex < outboundOrder.length; orderIndex++) {
      const index: number = outboundOrder[orderIndex];
      const node: XrayNode = nodes[index];
      outbounds.push('{' +
        '"tag":"node-' + index + '","protocol":"vless","settings":{"vnext":[{' +
          '"address":' + quote(node.server) + ',"port":' + node.port + ',"users":[{' +
            '"id":' + quote(node.uuid) + ',"encryption":"none","flow":' + quote(node.flow) +
          '}]' +
        '}]},' +
        '"streamSettings":{"network":"tcp","security":"reality","realitySettings":{' +
          '"serverName":' + quote(node.serverName) + ',' +
          '"fingerprint":' + quote(node.fingerprint) + ',' +
          '"publicKey":' + quote(node.publicKey) + ',' +
          '"shortId":' + quote(node.shortId) + ',"spiderX":"/"' +
        '}}' +
      '}');
    }
    outbounds.push('{"tag":"direct","protocol":"freedom","settings":{}}');
    const selectedTag: string = 'node-' + selectedIndex;
    if (mode === 'direct') {
      routingRules.push('{"type":"field","inboundTag":["tun-in"],"outboundTag":"direct"}');
    } else if (mode === 'global') {
      routingRules.push('{"type":"field","inboundTag":["tun-in"],"outboundTag":' +
        quote(selectedTag) + '}');
    } else {
      routingRules.push('{' +
        '"type":"field","ip":["10.0.0.0/8","172.16.0.0/12","192.168.0.0/16",' +
        '"127.0.0.0/8","169.254.0.0/16"],"outboundTag":"direct"' +
      '}');
      const clashRules: string[] = this.buildClashRules(profile, selectedTag, quote);
      for (let index: number = 0; index < clashRules.length; index++) {
        routingRules.push(clashRules[index]);
      }
      routingRules.push('{"type":"field","inboundTag":["tun-in"],"outboundTag":' +
        quote(selectedTag) + '}');
    }

    return '{' +
      '"inbounds":[' + inbounds.join(',') + '],' +
      '"outbounds":[' + outbounds.join(',') + '],' +
      '"routing":{"domainStrategy":"AsIs","rules":[' + routingRules.join(',') + ']} ,' +
      '"dns":{"queryStrategy":"UseIPv4","fakeIp":{' +
        '"enabled":true,"ipv4Pool":"198.19.0.0/16","poolSize":32768,"ttl":60' +
      '}}' +
    '}';
  }

  private buildClashRules(profile: string, selectedTag: string,
    quote: (value: string) => string): string[] {
    const output: string[] = [];
    const lines: string[] = profile.split('\n');
    let inRules: boolean = false;
    for (let index: number = 0; index < lines.length && output.length < 500; index++) {
      const line: string = lines[index];
      if (line.trim() === 'rules:') {
        inRules = true;
        continue;
      }
      if (inRules && line.length > 0 && line[0] !== ' ' && line[0] !== '\t') {
        break;
      }
      if (!inRules || !/^\s*-\s*/.test(line)) {
        continue;
      }
      let rule: string = line.replace(/^\s*-\s*/, '').trim();
      rule = rule.replace(/^['"]|['"]$/g, '');
      const fields: string[] = rule.split(',').map((value: string) => value.trim());
      if (fields.length < 2) {
        continue;
      }
      const kind: string = fields[0].toUpperCase();
      const policy: string = fields[fields.length - 1].toUpperCase();
      if (policy === 'REJECT' || policy === 'REJECT-DROP') {
        continue;
      }
      const outbound: string = policy === 'DIRECT' ? 'direct' : selectedTag;
      if (kind === 'DOMAIN' && fields.length >= 3) {
        output.push('{"type":"field","domain":[' + quote('full:' + fields[1]) +
          '],"outboundTag":' + quote(outbound) + '}');
      } else if (kind === 'DOMAIN-SUFFIX' && fields.length >= 3) {
        output.push('{"type":"field","domain":[' + quote('domain:' + fields[1]) +
          '],"outboundTag":' + quote(outbound) + '}');
      } else if (kind === 'DOMAIN-KEYWORD' && fields.length >= 3) {
        output.push('{"type":"field","domain":[' + quote(fields[1]) +
          '],"outboundTag":' + quote(outbound) + '}');
      } else if ((kind === 'IP-CIDR' || kind === 'IP-CIDR6') && fields.length >= 3) {
        output.push('{"type":"field","ip":[' + quote(fields[1]) +
          '],"outboundTag":' + quote(outbound) + '}');
      } else if (kind === 'MATCH' || kind === 'FINAL') {
        output.push('{"type":"field","inboundTag":["tun-in"],"outboundTag":' +
          quote(outbound) + '}');
      }
    }
    return output;
  }

  private extractRealityNodes(profile: string): XrayNode[] {
    const nodes: XrayNode[] = [];
    const lines: string[] = profile.split('\n');
    let inProxies: boolean = false;
    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index];
      if (line.trim() === 'proxies:') {
        inProxies = true;
        continue;
      }
      if (inProxies && line.length > 0 && line[0] !== ' ' && line[0] !== '\t') {
        break;
      }
      const trimmed: string = line.trim();
      if (!inProxies || !trimmed.startsWith('- {') || !trimmed.endsWith('}')) {
        continue;
      }
      const mapText: string = trimmed.substring(2).trim();
      const values: Map<string, string> = this.parseInlineMap(mapText);
      if (this.unquote(values.get('type') ?? '') !== 'vless' || !values.has('reality-opts')) {
        continue;
      }
      const reality: Map<string, string> = this.parseInlineMap(values.get('reality-opts') ?? '');
      const node: XrayNode = {
        name: this.unquote(values.get('name') ?? ''),
        server: this.unquote(values.get('server') ?? ''),
        port: Number(this.unquote(values.get('port') ?? '0')),
        uuid: this.unquote(values.get('uuid') ?? ''),
        flow: this.unquote(values.get('flow') ?? 'xtls-rprx-vision'),
        fingerprint: this.unquote(values.get('client-fingerprint') ?? 'chrome'),
        serverName: this.unquote(values.get('servername') ?? ''),
        publicKey: this.unquote(reality.get('public-key') ?? ''),
        shortId: this.unquote(reality.get('short-id') ?? '')
      };
      if (node.name.length > 0 && node.server.length > 0 && node.port > 0 &&
        node.uuid.length > 0 && node.serverName.length > 0 && node.publicKey.length > 0) {
        nodes.push(node);
      }
    }
    return nodes;
  }

  private parseInlineMap(raw: string): Map<string, string> {
    let text: string = raw.trim();
    if (text.startsWith('{') && text.endsWith('}')) {
      text = text.substring(1, text.length - 1);
    }
    const result: Map<string, string> = new Map<string, string>();
    const entries: string[] = this.splitTopLevel(text, ',');
    for (let index: number = 0; index < entries.length; index++) {
      const pair: string[] = this.splitTopLevel(entries[index], ':');
      if (pair.length >= 2) {
        result.set(pair[0].trim(), pair.slice(1).join(':').trim());
      }
    }
    return result;
  }

  private splitTopLevel(text: string, delimiter: string): string[] {
    const parts: string[] = [];
    let start: number = 0;
    let depth: number = 0;
    let quote: string = '';
    let escaped: boolean = false;
    for (let index: number = 0; index < text.length; index++) {
      const character: string = text[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (quote.length > 0 && character === '\\') {
        escaped = true;
        continue;
      }
      if (character === '"' || character === "'") {
        if (quote === character) {
          quote = '';
        } else if (quote.length === 0) {
          quote = character;
        }
        continue;
      }
      if (quote.length > 0) {
        continue;
      }
      if (character === '{' || character === '[') {
        depth++;
      } else if (character === '}' || character === ']') {
        depth--;
      } else if (character === delimiter && depth === 0) {
        parts.push(text.substring(start, index));
        start = index + 1;
      }
    }
    parts.push(text.substring(start));
    return parts;
  }

  private unquote(raw: string): string {
    const value: string = raw.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      try {
        return JSON.parse(value) as string;
      } catch (_error) {
        return value.substring(1, value.length - 1);
      }
    }
    if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1).replace(/''/g, "'");
    }
    return value;
  }
}

export const xrayProfileService: XrayProfileService = new XrayProfileService();
