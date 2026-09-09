import { fileIo } from '@kit.CoreFileKit';
import { CoreStatus, TrafficStats, TunnelState } from './CoreTypes';

const RUNTIME_STATE_NAME: string = 'runtime-status.json';
const RUNTIME_TRAFFIC_NAME: string = 'runtime-traffic.json';
const HEARTBEAT_MAX_AGE_MS: number = 12000;

interface StoredRuntimeState {
  state: string;
  message: string;
  connectedAt: number;
}

interface StoredTrafficState {
  uploadBytes: number;
  downloadBytes: number;
  activeConnections: number;
  updatedAt: number;
  inboundPackets?: number;
  outboundPackets?: number;
  droppedPackets?: number;
  tcpOpenErrors?: number;
  udpOpenErrors?: number;
  udpQuicBlockedPackets?: number;
  udpVisionRejections?: number;
}

export class RuntimeStateService {
  private path(filesDir: string): string {
    return `${filesDir}/${RUNTIME_STATE_NAME}`;
  }

  private trafficPath(filesDir: string): string {
    return `${filesDir}/${RUNTIME_TRAFFIC_NAME}`;
  }

  clear(filesDir: string): void {
    const path: string = this.path(filesDir);
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (_error) {
      // A missing/stale state file is equivalent to no runtime state.
    }
    try {
      const trafficPath: string = this.trafficPath(filesDir);
      if (fileIo.accessSync(trafficPath)) fileIo.unlinkSync(trafficPath);
    } catch (_error) {
    }
  }

  write(filesDir: string, status: CoreStatus): void {
    const path: string = this.path(filesDir);
    try {
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      const stored: StoredRuntimeState = {
        state: status.state,
        message: status.message,
        connectedAt: status.state === TunnelState.CONNECTED ? Date.now() : 0
      };
      try {
        fileIo.writeSync(file.fd, JSON.stringify(stored));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_error) {
      // Runtime state is advisory. VPN fail-close behavior must not depend on it.
    }
  }

  read(filesDir: string): CoreStatus | undefined {
    try {
      const stored: StoredRuntimeState = JSON.parse(fileIo.readTextSync(this.path(filesDir))) as StoredRuntimeState;
      if (stored.state === TunnelState.CONNECTED) {
        return { state: TunnelState.CONNECTED, message: stored.message };
      }
      if (stored.state === TunnelState.FAILED) {
        return { state: TunnelState.FAILED, message: stored.message };
      }
      if (stored.state === TunnelState.DISCONNECTED) {
        return { state: TunnelState.DISCONNECTED, message: stored.message };
      }
    } catch (_error) {
      return undefined;
    }
    return undefined;
  }

  getConnectedAt(filesDir: string): number {
    try {
      const stored: StoredRuntimeState = JSON.parse(fileIo.readTextSync(this.path(filesDir))) as StoredRuntimeState;
      return stored.state === TunnelState.CONNECTED ? (stored.connectedAt ?? 0) : 0;
    } catch (_error) {
      return 0;
    }
  }

  writeTraffic(filesDir: string, stats: TrafficStats): void {
    const path: string = this.trafficPath(filesDir);
    try {
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      const stored: StoredTrafficState = {
        uploadBytes: stats.uploadBytes,
        downloadBytes: stats.downloadBytes,
        activeConnections: stats.activeConnections,
        updatedAt: Date.now(),
        inboundPackets: stats.inboundPackets,
        outboundPackets: stats.outboundPackets,
        droppedPackets: stats.droppedPackets,
        tcpOpenErrors: stats.tcpOpenErrors,
        udpOpenErrors: stats.udpOpenErrors,
        udpQuicBlockedPackets: stats.udpQuicBlockedPackets,
        udpVisionRejections: stats.udpVisionRejections
      };
      try {
        fileIo.writeSync(file.fd, JSON.stringify(stored));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_error) {
      // Statistics are best-effort and must never affect packet processing.
    }
  }

  readTraffic(filesDir: string): TrafficStats {
    try {
      const stored: StoredTrafficState = JSON.parse(
        fileIo.readTextSync(this.trafficPath(filesDir))) as StoredTrafficState;
      return {
        uploadBytes: stored.uploadBytes ?? 0,
        downloadBytes: stored.downloadBytes ?? 0,
        activeConnections: stored.activeConnections ?? 0,
        inboundPackets: stored.inboundPackets ?? 0,
        outboundPackets: stored.outboundPackets ?? 0,
        droppedPackets: stored.droppedPackets ?? 0,
        tcpOpenErrors: stored.tcpOpenErrors ?? 0,
        udpOpenErrors: stored.udpOpenErrors ?? 0,
        udpQuicBlockedPackets: stored.udpQuicBlockedPackets ?? 0,
        udpVisionRejections: stored.udpVisionRejections ?? 0
      };
    } catch (_error) {
      return { uploadBytes: 0, downloadBytes: 0, activeConnections: 0 };
    }
  }

  isHeartbeatFresh(filesDir: string): boolean {
    try {
      const stored: StoredTrafficState = JSON.parse(
        fileIo.readTextSync(this.trafficPath(filesDir))) as StoredTrafficState;
      return stored.updatedAt > 0 && Date.now() - stored.updatedAt <= HEARTBEAT_MAX_AGE_MS;
    } catch (_error) {
      return false;
    }
  }
}

export const runtimeStateService: RuntimeStateService = new RuntimeStateService();
