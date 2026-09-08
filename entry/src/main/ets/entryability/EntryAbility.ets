import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0xC105;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;

  private updateSystemBars(dark: boolean): void {
    if (!this.mainWindow) return;
    const background: string = dark ? '#0F1115' : '#F3F6FC';
    const content: string = dark ? '#F3F4F6' : '#172033';
    this.mainWindow.setWindowSystemBarProperties({
      statusBarColor: background,
      navigationBarColor: background,
      statusBarContentColor: content,
      navigationBarContentColor: content,
      isStatusBarLightIcon: dark,
      isNavigationBarLightIcon: dark,
      enableStatusBarAnimation: true,
      enableNavigationBarAnimation: true
    }).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'Failed to update system bars: %{public}s', error.message);
    });
    this.mainWindow.setSpecificSystemBarEnabled('navigationIndicator', !dark).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'Failed to update navigation indicator: %{public}s', error.message);
    });
  }

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Clash HOS created');
    AppStorage.setOrCreate('isDarkMode',
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const dark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate('isDarkMode', dark);
    this.updateSystemBars(dark);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      this.mainWindow = windowStage.getMainWindowSync();
      this.updateSystemBars(
        this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to obtain main window: %{public}s', (error as Error).message);
    }
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', error.message);
        return;
      }
      hilog.info(DOMAIN, TAG, 'Content loaded');
    });
  }
}
