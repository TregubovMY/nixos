# Firefox: меньше телеметрии и меньше памяти. Запрошено live 2026-10-20
# (на хосте Firefox занимал ~6,5 ГБ на десятках вкладок).
#
# Источники: K3V1991/Disable-Firefox-Telemetry-and-Data-Collection (список
# telemetry-prefs), itshaman.ru/articles/3954 (browser.sessionhistory.
# max_entries), Mozilla Support/Connect (dom.ipc.processCount.webIsolated,
# browser.tabs.unloadOnLowMemory). Fission (site isolation) НЕ выключаем --
# это security-граница; память режем числом процессов и выгрузкой вкладок.
#
# Политики (enterprise policies) надёжнее about:config-prefs: Firefox не
# перезаписывает их при обновлении профиля. Prefs ниже ставятся со статусом
# "default" -- их можно переопределить в about:config, не лочатся.
{ ... }:
{
  programs.firefox = {
    enable = true; # заодно ставит пакет, отдельный `firefox` в systemPackages не нужен

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableFeedbackCommands = true;
      DisableFirefoxAccounts = false; # sync не трогаем
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      FirefoxHome = {
        Pocket = false;
        SponsoredPocket = false;
        SponsoredTopSites = false;
        Snippets = false;
      };
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        SkipOnboarding = true;
      };
    };

    preferencesStatus = "default";
    preferences = {
      # --- телеметрия / сбор данных (K3V1991) ---
      "browser.newtabpage.activity-stream.feeds.telemetry" = false;
      "browser.newtabpage.activity-stream.telemetry" = false;
      "browser.ping-centre.telemetry" = false;
      "datareporting.healthreport.service.enabled" = false;
      "datareporting.healthreport.uploadEnabled" = false;
      "datareporting.policy.dataSubmissionEnabled" = false;
      "toolkit.telemetry.archive.enabled" = false;
      "toolkit.telemetry.bhrPing.enabled" = false;
      "toolkit.telemetry.enabled" = false;
      "toolkit.telemetry.firstShutdownPing.enabled" = false;
      "toolkit.telemetry.hybridContent.enabled" = false;
      "toolkit.telemetry.newProfilePing.enabled" = false;
      "toolkit.telemetry.reportingpolicy.firstRun" = false;
      "toolkit.telemetry.server" = "";
      "toolkit.telemetry.shutdownPingSender.enabled" = false;
      "toolkit.telemetry.unified" = false;
      "toolkit.telemetry.updatePing.enabled" = false;
      "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;
      "app.shield.optoutstudies.enabled" = false;

      # --- память ---
      # История переходов на вкладку: по умолчанию 50 записей на вкладку.
      "browser.sessionhistory.max_entries" = 10;
      # При нехватке RAM выгружать давно неактивные вкладки (about:unloads).
      "browser.tabs.unloadOnLowMemory" = true;
      # Не больше 4 content-процессов (по умолчанию 8)...
      "dom.ipc.processCount" = 4;
      # ...и один процесс на сайт-origin вместо нескольких при Fission.
      "dom.ipc.processCount.webIsolated" = 1;
      # Не держать в памяти предзагруженные/закэшированные страницы bfcache.
      "browser.sessionhistory.max_total_viewers" = 2;
      # Реже писать сессию на диск (по умолчанию 15 с).
      "browser.sessionstore.interval" = 60000;
      # Кэш изображений/декодированных данных в RAM -- ограничить.
      "browser.cache.memory.capacity" = 262144; # КБ = 256 МБ
    };
  };
}
