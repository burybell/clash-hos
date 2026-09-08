import { http } from '@kit.NetworkKit';
import { TrafficStats } from './CoreTypes';

const CONTROLLER_BASE: string = 'http://127.0.0.1:9090';
const LATENCY_TEST_URL: string = 'https://www.gstatic.com/generate_204';
const XRAY_LATENCY_PORT_BASE: number = 17900;

interface DelayResponse {
  delay: number;
  overall?: number;
}

interface ConnectionsResponse {
  uploadTotal: number;
  downloadTotal: number;
  connections: Object[];
}

export interface NodeDelayResult {
  name: string;
  delay: number;
  available: boolean;
}

export class CoreControllerService {
  async getTrafficStats(): Promise<TrafficStats> {
    const first: TrafficStats = await this.getTrafficSnapshot();
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 400));
    const second: TrafficStats = await this.getTrafficSnapshot();
    return {
      uploadBytes: Math.max(0, second.uploadBytes - first.uploadBytes) / 0.4,
      downloadBytes: Math.max(0, second.downloadBytes - first.downloadBytes) / 0.4,
      activeConnections: second.activeConnections
    };
  }

  private async getTrafficSnapshot(): Promise<TrafficStats> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${CONTROLLER_BASE}/connections`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 800,
        readTimeout: 1200,
        usingCache: false
      });
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        typeof response.result !== 'string') {
        return { uploadBytes: 0, downloadBytes: 0, activeConnections: 0 };
      }
      const result: ConnectionsResponse = JSON.parse(response.result) as ConnectionsResponse;
      return {
        uploadBytes: result.uploadTotal ?? 0,
        downloadBytes: result.downloadTotal ?? 0,
        activeConnections: result.connections?.length ?? 0
      };
    } catch (_error) {
      return { uploadBytes: 0, downloadBytes: 0, activeConnections: 0 };
    } finally {
      request.destroy();
    }
  }

  async waitUntilReady(): Promise<boolean> {
    for (let attempt: number = 0; attempt < 20; attempt += 1) {
      const request: http.HttpRequest = http.createHttp();
      try {
        const response: http.HttpResponse = await request.request(`${CONTROLLER_BASE}/version`, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 500,
          readTimeout: 500,
          usingCache: false
        });
        if (response.responseCode >= 200 && response.responseCode < 300) return true;
      } catch (_error) {
      } finally {
        request.destroy();
      }
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 250));
    }
    return false;
  }

  async testNode(name: string, index: number = -1): Promise<NodeDelayResult> {
    if (index >= 0) {
      return this.testXrayNode(name, index);
    }
    const path: string = `/proxies/${encodeURIComponent(name)}/delay`;
    const query: string = `timeout=8000&url=${encodeURIComponent(LATENCY_TEST_URL)}`;
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${CONTROLLER_BASE}${path}?${query}`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 3000,
        readTimeout: 10000,
        usingCache: false
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return { name, delay: 0, available: false };
      }
      const result: DelayResponse = JSON.parse(response.result) as DelayResponse;
      return {
        name,
        delay: result.delay,
        available: result.delay > 0
      };
    } catch (_error) {
      return { name, delay: 0, available: false };
    } finally {
      request.destroy();
    }
  }

  private async testXrayNode(name: string, index: number): Promise<NodeDelayResult> {
    const request: http.HttpRequest = http.createHttp();
    const startedAt: number = Date.now();
    try {
      const response: http.HttpResponse = await request.request(LATENCY_TEST_URL, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 3000,
        readTimeout: 10000,
        usingCache: false,
        usingProxy: {
          host: '127.0.0.1',
          port: XRAY_LATENCY_PORT_BASE + index,
          exclusionList: []
        }
      });
      const delay: number = Date.now() - startedAt;
      return {
        name,
        delay,
        available: response.responseCode >= 200 && response.responseCode < 400
      };
    } catch (_error) {
      return { name, delay: 0, available: false };
    } finally {
      request.destroy();
    }
  }

  async selectNode(groupName: string, nodeName: string): Promise<boolean> {
    if (groupName.length === 0) {
      return false;
    }
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(
        `${CONTROLLER_BASE}/proxies/${encodeURIComponent(groupName)}`, {
          method: http.RequestMethod.PUT,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 3000,
          readTimeout: 5000,
          header: { 'Content-Type': 'application/json' },
          extraData: JSON.stringify({ name: nodeName })
        });
      return response.responseCode >= 200 && response.responseCode < 300;
    } catch (_error) {
      return false;
    } finally {
      request.destroy();
    }
  }
}

export const coreControllerService: CoreControllerService = new CoreControllerService();
