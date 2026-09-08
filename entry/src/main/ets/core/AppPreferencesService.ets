import { fileIo } from '@kit.CoreFileKit';

const SETTINGS_FILE: string = 'app-settings.json';

export type RoutingMode = 'rule' | 'global' | 'direct';

interface StoredSettings {
  routingMode: string;
  autoUpdateHours: number;
  autoSelectNode: boolean;
  preferredCountries: string[];
}

export class AppPreferencesService {
  getRoutingMode(filesDir: string): RoutingMode {
    const settings: StoredSettings = this.read(filesDir);
    if (settings.routingMode === 'global' || settings.routingMode === 'direct') {
      return settings.routingMode;
    }
    return 'rule';
  }

  setRoutingMode(filesDir: string, mode: RoutingMode): void {
    const settings: StoredSettings = this.read(filesDir);
    settings.routingMode = mode;
    this.write(filesDir, settings);
  }

  getAutoUpdateHours(filesDir: string): number {
    return this.read(filesDir).autoUpdateHours;
  }

  setAutoUpdateHours(filesDir: string, hours: number): void {
    const settings: StoredSettings = this.read(filesDir);
    settings.autoUpdateHours = hours;
    this.write(filesDir, settings);
  }

  getAutoSelectNode(filesDir: string): boolean {
    return this.read(filesDir).autoSelectNode;
  }

  setAutoSelectNode(filesDir: string, enabled: boolean): void {
    const settings: StoredSettings = this.read(filesDir);
    settings.autoSelectNode = enabled;
    this.write(filesDir, settings);
  }

  getPreferredCountries(filesDir: string): string[] {
    return this.read(filesDir).preferredCountries;
  }

  setPreferredCountries(filesDir: string, countries: string[]): void {
    const settings: StoredSettings = this.read(filesDir);
    settings.preferredCountries = countries;
    this.write(filesDir, settings);
  }

  private read(filesDir: string): StoredSettings {
    try {
      const parsed: StoredSettings = JSON.parse(
        fileIo.readTextSync(`${filesDir}/${SETTINGS_FILE}`)) as StoredSettings;
      return {
        routingMode: parsed.routingMode ?? 'rule',
        autoUpdateHours: parsed.autoUpdateHours ?? 24,
        autoSelectNode: parsed.autoSelectNode ?? false,
        preferredCountries: parsed.preferredCountries ?? ['香港', '日本', '新加坡']
      };
    } catch (_error) {
      return {
        routingMode: 'rule', autoUpdateHours: 24,
        autoSelectNode: false, preferredCountries: ['香港', '日本', '新加坡']
      };
    }
  }

  private write(filesDir: string, settings: StoredSettings): void {
    const file: fileIo.File = fileIo.openSync(`${filesDir}/${SETTINGS_FILE}`,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(settings));
    } finally {
      fileIo.closeSync(file);
    }
  }
}

export const appPreferencesService: AppPreferencesService = new AppPreferencesService();
