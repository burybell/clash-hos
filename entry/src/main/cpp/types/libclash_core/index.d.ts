export interface NativeCoreStatus {
  available: boolean;
  running: boolean;
  runtimeAbi: number;
  message: string;
}

export interface NativeTrafficStats {
  uploadBytes: number;
  downloadBytes: number;
  activeConnections: number;
  inboundPackets?: number;
  outboundPackets?: number;
  droppedPackets?: number;
  tcpOpenErrors?: number;
  udpOpenErrors?: number;
  udpQuicBlockedPackets?: number;
  udpVisionRejections?: number;
}

export const getStatus: () => NativeCoreStatus;
export const start: (config: string, workDir: string, tunFd: number) => NativeCoreStatus;
export const stop: () => NativeCoreStatus;
export const probeCompatibilityCore: () => boolean;
export const getCompatibilityCoreStatus: () => string;
export const getTrafficStats: () => NativeTrafficStats;
