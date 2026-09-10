import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { xrayProfileService } from '../core/XrayProfileService';

const MAX_BYTES: number = 8 * 1024 * 1024;
const ACTIVE_FILE: string = 'active.yaml';
const INDEX_FILE: string = 'subscriptions.json';
const LEGACY_FILE: string = 'subscription.json';
const SELECTED_FILE: string = 'selected-proxy.txt';

export interface SubscriptionImportResult {
  id: string;
  profilePath: string;
  byteLength: number;
  updatedAt: number;
  proxyNames: string[];
  rollback?: SubscriptionUpdateSnapshot;
}

export interface SubscriptionUpdateSnapshot {
  id: string;
  profile: string;
  activeProfile: string;
  index: string;
}

export interface SubscriptionActivationSnapshot {
  index: string;
  activeProfile: string;
  selectedProxy: string;
}

export interface SubscriptionInfo {
  id: string;
  name: string;
  url: string;
  displayUrl: string;
  updatedAt: number;
  byteLength: number;
  proxyNames: string[];
  selectorGroupName: string;
  engine: 'xray' | 'clashrs';
  protocols: string[];
  active: boolean;
}

interface StoredSubscription {
  id: string;
  name: string;
  url: string;
  updatedAt: number;
  byteLength: number;
}

interface StoredIndex {
  activeId: string;
  subscriptions: StoredSubscription[];
}

interface LegacyMetadata {
  url: string;
  updatedAt: number;
  byteLength: number;
}

interface DownloadedProfile {
  profile: string;
  byteLength: number;
  suggestedName: string;
}

export class SubscriptionService {
  getSelectedProxy(filesDir: string): string {
    try {
      return fileIo.readTextSync(`${this.dir(filesDir)}/${SELECTED_FILE}`).trim();
    } catch (_error) {
      return '';
    }
  }

  saveSelectedProxy(filesDir: string, name: string): void {
    this.ensureDir(filesDir);
    this.write(`${this.dir(filesDir)}/${SELECTED_FILE}`, name);
  }

  hasActiveProfile(filesDir: string): boolean {
    try {
      return fileIo.accessSync(`${this.dir(filesDir)}/${ACTIVE_FILE}`);
    } catch (_error) {
      return false;
    }
  }

  getSubscriptionInfo(filesDir: string): SubscriptionInfo | undefined {
    const items: SubscriptionInfo[] = this.listSubscriptions(filesDir);
    return items.find((item: SubscriptionInfo) => item.active);
  }

  listSubscriptions(filesDir: string): SubscriptionInfo[] {
    const index: StoredIndex = this.loadIndex(filesDir);
    const result: SubscriptionInfo[] = [];
    index.subscriptions.forEach((item: StoredSubscription) => {
      try {
        const profile: string = fileIo.readTextSync(this.profilePath(filesDir, item.id));
        result.push({
          id: item.id,
          name: item.name,
          url: item.url,
          displayUrl: this.maskUrl(item.url),
          updatedAt: item.updatedAt,
          byteLength: item.byteLength,
          proxyNames: this.extractProxyNames(profile),
          selectorGroupName: this.extractSelectorGroupName(profile),
          engine: xrayProfileService.shouldTranslate(profile) ? 'xray' : 'clashrs',
          protocols: this.extractProtocols(profile),
          active: item.id === index.activeId
        });
      } catch (_error) {
        // Broken profiles are omitted from the product UI.
      }
    });
    return result;
  }

  async importFromUrl(rawUrl: string, filesDir: string): Promise<SubscriptionImportResult> {
    const active: SubscriptionInfo | undefined = this.getSubscriptionInfo(filesDir);
    return active ? this.updateFromUrl(active.id, rawUrl, filesDir) : this.addFromUrl(rawUrl, filesDir);
  }

  async addFromUrl(rawUrl: string, filesDir: string, name: string = ''):
    Promise<SubscriptionImportResult> {
    const url: string = rawUrl.trim();
    const downloaded: DownloadedProfile = await this.download(url);
    const index: StoredIndex = this.loadIndex(filesDir);
    const id: string = `profile-${Date.now()}-${index.subscriptions.length + 1}`;
    const updatedAt: number = Date.now();
    const resolvedName: string = name.trim().length > 0 ? name.trim() :
      (downloaded.suggestedName.length > 0 ? downloaded.suggestedName : `订阅 ${index.subscriptions.length + 1}`);
    this.write(this.profilePath(filesDir, id), downloaded.profile);
    index.subscriptions.push({ id, name: resolvedName, url, updatedAt, byteLength: downloaded.byteLength });
    if (index.activeId.length === 0) {
      index.activeId = id;
      this.write(`${this.dir(filesDir)}/${ACTIVE_FILE}`, downloaded.profile);
    }
    this.saveIndex(filesDir, index);
    return this.result(id, downloaded, updatedAt, filesDir);
  }

  async updateSubscription(id: string, filesDir: string): Promise<SubscriptionImportResult> {
    const index: StoredIndex = this.loadIndex(filesDir);
    const item: StoredSubscription | undefined = this.find(index, id);
    if (!item || item.url.length === 0) {
      throw new Error('此配置没有可更新的订阅地址');
    }
    return this.updateFromUrl(id, item.url, filesDir);
  }

  rollbackUpdate(snapshot: SubscriptionUpdateSnapshot, filesDir: string): void {
    if (snapshot.id.length === 0 || snapshot.profile.length === 0 || snapshot.index.length === 0) {
      throw new Error('配置回滚快照无效');
    }
    this.validateProfile(snapshot.profile);
    this.write(this.profilePath(filesDir, snapshot.id), snapshot.profile);
    if (snapshot.activeProfile.length > 0) {
      this.write(`${this.dir(filesDir)}/${ACTIVE_FILE}`, snapshot.activeProfile);
    }
    this.write(`${this.dir(filesDir)}/${INDEX_FILE}`, snapshot.index);
  }

  activateSubscription(id: string, filesDir: string): SubscriptionInfo {
    const index: StoredIndex = this.loadIndex(filesDir);
    if (!this.find(index, id)) {
      throw new Error('找不到要启用的配置');
    }
    const profile: string = fileIo.readTextSync(this.profilePath(filesDir, id));
    this.validateProfile(profile);
    const snapshot: SubscriptionActivationSnapshot = this.captureActivationSnapshot(filesDir);
    try {
      this.write(`${this.dir(filesDir)}/${ACTIVE_FILE}`, profile);
      index.activeId = id;
      this.saveIndex(filesDir, index);
      this.write(`${this.dir(filesDir)}/${SELECTED_FILE}`, '');
    } catch (error) {
      this.rollbackActivation(snapshot, filesDir);
      throw error as Error;
    }
    const active: SubscriptionInfo | undefined = this.getSubscriptionInfo(filesDir);
    if (!active) {
      throw new Error('配置启用失败');
    }
    return active;
  }

  captureActivationSnapshot(filesDir: string): SubscriptionActivationSnapshot {
    const index: StoredIndex = this.loadIndex(filesDir);
    let activeProfile: string = '';
    if (index.activeId.length > 0) {
      activeProfile = fileIo.readTextSync(`${this.dir(filesDir)}/${ACTIVE_FILE}`);
    }
    return {
      index: JSON.stringify(index),
      activeProfile,
      selectedProxy: this.getSelectedProxy(filesDir)
    };
  }

  rollbackActivation(snapshot: SubscriptionActivationSnapshot, filesDir: string): void {
    if (snapshot.index.length === 0) throw new Error('配置切换回滚快照无效');
    if (snapshot.activeProfile.length > 0) {
      this.validateProfile(snapshot.activeProfile);
      this.write(`${this.dir(filesDir)}/${ACTIVE_FILE}`, snapshot.activeProfile);
    }
    this.write(`${this.dir(filesDir)}/${INDEX_FILE}`, snapshot.index);
    this.write(`${this.dir(filesDir)}/${SELECTED_FILE}`, snapshot.selectedProxy);
  }

  renameSubscription(id: string, name: string, filesDir: string): void {
    const value: string = name.trim();
    if (value.length === 0 || value.length > 40) {
      throw new Error('配置名称应为 1–40 个字符');
    }
    const index: StoredIndex = this.loadIndex(filesDir);
    const item: StoredSubscription | undefined = this.find(index, id);
    if (!item) {
      throw new Error('找不到要重命名的配置');
    }
    item.name = value;
    this.saveIndex(filesDir, index);
  }

  deleteSubscription(id: string, filesDir: string): void {
    const index: StoredIndex = this.loadIndex(filesDir);
    const remaining: StoredSubscription[] = index.subscriptions.filter(
      (item: StoredSubscription) => item.id !== id);
    if (remaining.length === index.subscriptions.length) {
      return;
    }
    try {
      fileIo.unlinkSync(this.profilePath(filesDir, id));
    } catch (_error) {
    }
    index.subscriptions = remaining;
    if (index.activeId === id) {
      index.activeId = remaining.length > 0 ? remaining[0].id : '';
      if (index.activeId.length > 0) {
        this.write(`${this.dir(filesDir)}/${ACTIVE_FILE}`,
          fileIo.readTextSync(this.profilePath(filesDir, index.activeId)));
      } else {
        try {
          fileIo.unlinkSync(`${this.dir(filesDir)}/${ACTIVE_FILE}`);
        } catch (_error) {
        }
      }
    }
    this.saveIndex(filesDir, index);
  }

  private async updateFromUrl(id: string, url: string, filesDir: string): Promise<SubscriptionImportResult> {
    const downloaded: DownloadedProfile = await this.download(url.trim());
    const index: StoredIndex = this.loadIndex(filesDir);
    const item: StoredSubscription | undefined = this.find(index, id);
    if (!item) {
      throw new Error('找不到要更新的配置');
    }
    const snapshot: SubscriptionUpdateSnapshot = {
      id,
      profile: fileIo.readTextSync(this.profilePath(filesDir, id)),
      activeProfile: index.activeId === id ?
        fileIo.readTextSync(`${this.dir(filesDir)}/${ACTIVE_FILE}`) : '',
      index: JSON.stringify(index)
    };
    const updatedAt: number = Date.now();
    item.url = url.trim();
    item.updatedAt = updatedAt;
    item.byteLength = downloaded.byteLength;
    if (downloaded.suggestedName.length > 0 &&
      (item.name.startsWith('订阅 ') || item.name === '我的订阅')) {
      item.name = downloaded.suggestedName;
    }
    try {
      this.write(this.profilePath(filesDir, id), downloaded.profile);
      if (index.activeId === id) {
        this.write(`${this.dir(filesDir)}/${ACTIVE_FILE}`, downloaded.profile);
      }
      this.saveIndex(filesDir, index);
    } catch (error) {
      this.rollbackUpdate(snapshot, filesDir);
      throw error as Error;
    }
    return this.result(id, downloaded, updatedAt, filesDir, snapshot);
  }

  private result(id: string, downloaded: DownloadedProfile, updatedAt: number,
    filesDir: string, rollback?: SubscriptionUpdateSnapshot): SubscriptionImportResult {
    return {
      id,
      profilePath: this.profilePath(filesDir, id),
      byteLength: downloaded.byteLength,
      updatedAt,
      proxyNames: this.extractProxyNames(downloaded.profile),
      rollback
    };
  }

  private async download(url: string): Promise<DownloadedProfile> {
    this.validateUrl(url);
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        maxLimit: MAX_BYTES,
        usingCache: false,
        header: {
          'Accept': 'text/yaml, text/plain, application/yaml, */*',
          'User-Agent': 'clash.meta'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`订阅服务器返回 HTTP ${response.responseCode}`);
      }
      if (typeof response.result !== 'string') {
        throw new Error('订阅响应不是文本格式');
      }
      const profile: string = response.result.trim();
      this.validateProfile(profile);
      return {
        profile,
        byteLength: profile.length,
        suggestedName: this.extractSubscriptionName(response.header, profile)
      };
    } finally {
      request.destroy();
    }
  }

  private loadIndex(filesDir: string): StoredIndex {
    this.ensureDir(filesDir);
    try {
      return JSON.parse(fileIo.readTextSync(`${this.dir(filesDir)}/${INDEX_FILE}`)) as StoredIndex;
    } catch (_error) {
      return this.migrate(filesDir);
    }
  }

  private migrate(filesDir: string): StoredIndex {
    const empty: StoredIndex = { activeId: '', subscriptions: [] };
    let profile: string = '';
    try {
      profile = fileIo.readTextSync(`${this.dir(filesDir)}/${ACTIVE_FILE}`);
    } catch (_error) {
      return empty;
    }
    if (profile.trim().length === 0) {
      return empty;
    }
    let metadata: LegacyMetadata = { url: '', updatedAt: 0, byteLength: profile.length };
    try {
      metadata = JSON.parse(fileIo.readTextSync(`${this.dir(filesDir)}/${LEGACY_FILE}`)) as LegacyMetadata;
    } catch (_error) {
    }
    const id: string = 'profile-migrated';
    const migrated: StoredIndex = {
      activeId: id,
      subscriptions: [{ id, name: '我的订阅', url: metadata.url,
        updatedAt: metadata.updatedAt, byteLength: metadata.byteLength }]
    };
    this.write(this.profilePath(filesDir, id), profile);
    this.saveIndex(filesDir, migrated);
    return migrated;
  }

  private saveIndex(filesDir: string, index: StoredIndex): void {
    this.ensureDir(filesDir);
    this.write(`${this.dir(filesDir)}/${INDEX_FILE}`, JSON.stringify(index));
  }

  private find(index: StoredIndex, id: string): StoredSubscription | undefined {
    return index.subscriptions.find((item: StoredSubscription) => item.id === id);
  }

  private dir(filesDir: string): string {
    return `${filesDir}/profiles`;
  }

  private profilePath(filesDir: string, id: string): string {
    return `${this.dir(filesDir)}/${id}.yaml`;
  }

  private ensureDir(filesDir: string): void {
    const path: string = this.dir(filesDir);
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path, true);
      }
    } catch (_error) {
      fileIo.mkdirSync(path, true);
    }
  }

  private write(path: string, text: string): void {
    const temporaryPath: string = `${path}.tmp`;
    const file: fileIo.File = fileIo.openSync(temporaryPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, text);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(temporaryPath, path);
  }

  private validateUrl(url: string): void {
    if (url.length === 0) {
      throw new Error('请输入订阅链接');
    }
    if (url.length > 4096 || url.includes('\n') || url.includes('\r') || !url.startsWith('https://')) {
      throw new Error('请输入有效的 HTTPS 订阅链接');
    }
  }

  private validateProfile(profile: string): void {
    if (profile.length === 0) {
      throw new Error('订阅返回了空配置');
    }
    if (profile.length > MAX_BYTES) {
      throw new Error('订阅配置超过 8 MiB 限制');
    }
    if (!profile.includes('proxies:') && !profile.includes('proxy-providers:') &&
      !profile.includes('proxy-groups:')) {
      throw new Error('响应内容不是兼容 Clash 的 YAML 配置');
    }
  }

  private maskUrl(url: string): string {
    if (url.length === 0) {
      return '本地配置';
    }
    const query: number = url.indexOf('?');
    return query < 0 ? url : `${url.substring(0, query)}?••••••`;
  }

  private extractSubscriptionName(headers: Object, profile: string): string {
    const serialized: string = JSON.stringify(headers);
    const title: RegExpMatchArray | null = serialized.match(
      /["'](?:profile-title|profile_title)["']\s*:\s*(?:["']([^"']+)["']|\[["']([^"']+)["']\])/i);
    let value: string = title ? (title[1] || title[2] || '') : '';
    if (value.length === 0) {
      const disposition: RegExpMatchArray | null = serialized.match(/filename\*?=(?:UTF-8''|\\"|["'])?([^;"'\\]+)/i);
      value = disposition ? (disposition[1] || '') : '';
    }
    if (value.length === 0) {
      const yamlTitle: RegExpMatchArray | null = profile.match(/^profile-title:\s*(.+)$/mi);
      value = yamlTitle ? (yamlTitle[1] || '') : '';
    }
    try {
      value = decodeURIComponent(value);
    } catch (_error) {
      // Header is already plain text.
    }
    value = value.trim().replace(/^['"]|['"]$/g, '').replace(/\.(yaml|yml|json)$/i, '');
    return value.length > 60 ? value.substring(0, 60) : value;
  }

  private extractProxyNames(profile: string): string[] {
    if (xrayProfileService.shouldTranslate(profile)) {
      return xrayProfileService.supportedNodeNames(profile);
    }
    const names: string[] = [];
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
      if (!inProxies) {
        continue;
      }
      const block: RegExpMatchArray | null = line.match(/^\s*-\s*name:\s*(.+)\s*$/);
      const inline: RegExpMatchArray | null = line.match(
        /^\s*-\s*\{\s*name:\s*(?:"([^"]*)"|'([^']*)'|([^,}]+))/);
      let name: string = block && block[1] ? block[1].trim() :
        (inline ? (inline[1] || inline[2] || inline[3] || '').trim() : '');
      if ((name.startsWith('"') && name.endsWith('"')) ||
        (name.startsWith("'") && name.endsWith("'"))) {
        name = name.substring(1, name.length - 1);
      }
      if (name.length > 0 && !this.isInformationNode(name) && names.length < 200) {
        names.push(name);
      }
    }
    return names;
  }

  private extractProtocols(profile: string): string[] {
    if (xrayProfileService.shouldTranslate(profile)) {
      return ['VLESS REALITY Vision'];
    }
    const protocols: string[] = [];
    const lines: string[] = profile.split('\n');
    let inProxies: boolean = false;
    for (let index: number = 0; index < lines.length; index += 1) {
      const line: string = lines[index];
      if (line.trim() === 'proxies:') {
        inProxies = true;
        continue;
      }
      if (inProxies && line.length > 0 && line[0] !== ' ' && line[0] !== '\t') break;
      if (!inProxies) continue;
      const match: RegExpMatchArray | null = line.match(/(?:^\s+type:|[,\s]type:)\s*["']?([a-zA-Z0-9_-]+)/);
      if (!match || !match[1]) continue;
      const label: string = this.protocolLabel(match[1]);
      if (label.length > 0 && !protocols.includes(label)) protocols.push(label);
    }
    return protocols;
  }

  private protocolLabel(raw: string): string {
    const value: string = raw.toLowerCase();
    if (value === 'ss') return 'Shadowsocks';
    if (value === 'ssr') return 'ShadowsocksR';
    if (value === 'vmess') return 'VMess';
    if (value === 'vless') return 'VLESS';
    if (value === 'trojan') return 'Trojan';
    if (value === 'anytls') return 'AnyTLS';
    if (value === 'hysteria2' || value === 'hy2') return 'Hysteria2';
    if (value === 'tuic') return 'TUIC';
    if (value === 'socks5') return 'SOCKS5';
    if (value === 'http') return 'HTTP';
    if (value === 'wireguard') return 'WireGuard';
    return value.length > 0 ? value.toUpperCase() : '';
  }

  private isInformationNode(name: string): boolean {
    return /剩余流量|流量剩余|距离.*重置|重置.*剩余|套餐到期|到期时间|有效期|官网|客服|公告/i.test(name);
  }

  private extractSelectorGroupName(profile: string): string {
    const lines: string[] = profile.split('\n');
    let inGroups: boolean = false;
    let pending: string = '';
    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index];
      if (line.trim() === 'proxy-groups:') {
        inGroups = true;
        continue;
      }
      if (inGroups && line.length > 0 && line[0] !== ' ' && line[0] !== '\t') {
        break;
      }
      if (!inGroups) {
        continue;
      }
      const inline: RegExpMatchArray | null = line.match(
        /^\s*-\s*\{\s*name:\s*(?:"([^"]*)"|'([^']*)'|([^,}]+)).*\btype:\s*select\b/);
      if (inline) {
        return (inline[1] || inline[2] || inline[3] || '').trim();
      }
      const named: RegExpMatchArray | null = line.match(/^\s*-\s*name:\s*(.+)\s*$/);
      if (named && named[1]) {
        pending = named[1].trim().replace(/^['"]|['"]$/g, '');
      } else if (pending.length > 0 && /^\s+type:\s*select\s*$/.test(line)) {
        return pending;
      }
    }
    return '';
  }
}

export const subscriptionService: SubscriptionService = new SubscriptionService();
