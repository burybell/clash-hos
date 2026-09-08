import { fileIo } from '@kit.CoreFileKit';
import { CoreStatus, TunnelState } from './CoreTypes';

const RUNTIME_STATE_NAME: string = 'runtime-status.json';

interface StoredRuntimeState {
  state: string;
  message: string;
  connectedAt: number;
}

export class RuntimeStateService {
  private path(filesDir: string): string {
    return `${filesDir}/${RUNTIME_STATE_NAME}`;
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
}

export const runtimeStateService: RuntimeStateService = new RuntimeStateService();
