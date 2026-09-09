export enum TunnelState {
  DISCONNECTED = 'disconnected',
  STARTING = 'starting',
  CONNECTED = 'connected',
  STOPPING = 'stopping',
  FAILED = 'failed'
}

export interface CoreStatus {
  state: TunnelState;
  message: string;
}

export interface NativeCoreStatus {
  available: boolean;
  running: boolean;
  runtimeAbi: number;
  message: string;
}

export interface TrafficStats {
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
