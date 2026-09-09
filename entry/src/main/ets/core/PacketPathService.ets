import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DNS_SERVER: string = '1.1.1.1';
const DNS_PORT: number = 53;
const PROBE_TIMEOUT_MS: number = 5000;

export interface PacketProbeResult {
  dnsUdp: boolean;
  dnsTcp: boolean;
  dnsUdpMs: number;
  dnsTcpMs: number;
  detail: string;
}

export class PacketPathService {
  async run(): Promise<PacketProbeResult> {
    const query: ArrayBuffer = this.buildDnsQuery();
    const udpStarted: number = Date.now();
    const dnsUdp: boolean = await this.probeUdp(query);
    const dnsUdpMs: number = dnsUdp ? Date.now() - udpStarted : 0;
    const tcpStarted: number = Date.now();
    const dnsTcp: boolean = await this.probeTcp(query);
    const dnsTcpMs: number = dnsTcp ? Date.now() - tcpStarted : 0;
    let detail: string = 'DNS UDP 与 TCP 数据通路正常';
    if (!dnsUdp && dnsTcp) detail = 'DNS UDP 不可用，TCP 回退正常';
    if (dnsUdp && !dnsTcp) detail = 'DNS UDP 正常，TCP 回退不可用';
    if (!dnsUdp && !dnsTcp) detail = 'DNS UDP 与 TCP 数据通路均不可用';
    return { dnsUdp, dnsTcp, dnsUdpMs, dnsTcpMs, detail };
  }

  private async probeUdp(query: ArrayBuffer): Promise<boolean> {
    const client: socket.UDPSocket = socket.constructUDPSocketInstance();
    try {
      await client.bind({ address: '0.0.0.0', port: 0, family: 1 });
      const response: Promise<boolean> = new Promise<boolean>((resolve: (value: boolean) => void) => {
        let settled: boolean = false;
        const finish = (value: boolean): void => {
          if (settled) return;
          settled = true;
          resolve(value);
        };
        client.on('message', (message: socket.SocketMessageInfo): void => {
          finish(this.isDnsResponse(message.message, 0));
        });
        client.on('error', (_error: BusinessError): void => finish(false));
        setTimeout((): void => finish(false), PROBE_TIMEOUT_MS);
      });
      await client.send({ data: query, address: { address: DNS_SERVER, port: DNS_PORT, family: 1 } });
      return await response;
    } catch (_error) {
      return false;
    } finally {
      try { await client.close(); } catch (_error) {}
    }
  }

  private async probeTcp(query: ArrayBuffer): Promise<boolean> {
    const client: socket.TCPSocket = socket.constructTCPSocketInstance();
    try {
      await client.connect({ address: { address: DNS_SERVER, port: DNS_PORT, family: 1 },
        timeout: PROBE_TIMEOUT_MS });
      const response: Promise<boolean> = new Promise<boolean>((resolve: (value: boolean) => void) => {
        let settled: boolean = false;
        const finish = (value: boolean): void => {
          if (settled) return;
          settled = true;
          resolve(value);
        };
        client.on('message', (message: socket.SocketMessageInfo): void => {
          finish(this.isDnsResponse(message.message, 2));
        });
        client.on('error', (_error: BusinessError): void => finish(false));
        setTimeout((): void => finish(false), PROBE_TIMEOUT_MS);
      });
      await client.send({ data: this.withTcpLength(query) });
      return await response;
    } catch (_error) {
      return false;
    } finally {
      try { await client.close(); } catch (_error) {}
    }
  }

  private buildDnsQuery(): ArrayBuffer {
    const labels: string[] = ['example', 'com'];
    const length: number = 12 + 1 + 7 + 1 + 3 + 1 + 4;
    const bytes: Uint8Array = new Uint8Array(length);
    bytes[0] = 0x43;
    bytes[1] = 0x48;
    bytes[2] = 0x01;
    bytes[5] = 0x01;
    let offset: number = 12;
    labels.forEach((label: string) => {
      bytes[offset] = label.length;
      offset += 1;
      for (let index: number = 0; index < label.length; index += 1) {
        bytes[offset] = label.charCodeAt(index);
        offset += 1;
      }
    });
    bytes[offset] = 0;
    bytes[offset + 2] = 1;
    bytes[offset + 4] = 1;
    return bytes.buffer;
  }

  private withTcpLength(query: ArrayBuffer): ArrayBuffer {
    const payload: Uint8Array = new Uint8Array(query);
    const framed: Uint8Array = new Uint8Array(payload.length + 2);
    framed[0] = (payload.length >> 8) & 0xff;
    framed[1] = payload.length & 0xff;
    framed.set(payload, 2);
    return framed.buffer;
  }

  private isDnsResponse(buffer: ArrayBuffer, offset: number): boolean {
    const bytes: Uint8Array = new Uint8Array(buffer);
    return bytes.length >= offset + 12 && bytes[offset] === 0x43 && bytes[offset + 1] === 0x48 &&
      (bytes[offset + 2] & 0x80) !== 0;
  }
}

export const packetPathService: PacketPathService = new PacketPathService();
