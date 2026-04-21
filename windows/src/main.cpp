#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <ShlObj.h>
#include <dwmapi.h>
#include <commctrl.h>
#include <uxtheme.h>
#include <wrl.h>
#include <WebView2.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#pragma comment(lib, "Comctl32.lib")
#pragma comment(lib, "Dwmapi.lib")
#pragma comment(lib, "Shlwapi.lib")
#pragma comment(lib, "UxTheme.lib")

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

constexpr UINT kTitleBarHeight = 42;
constexpr BYTE kMinAlpha = 26;
constexpr BYTE kMaxAlpha = 255;
constexpr BYTE kAlphaStep = 4;
constexpr BYTE kMaxBlur = 180;
constexpr BYTE kBlurStep = 12;
constexpr int kMaxTabs = 10;

constexpr UINT kHotkeyTogglePanel = 1;
constexpr UINT kHotkeySwitchTab = 2;
constexpr UINT kHotkeyRefreshTab = 3;
constexpr UINT kHotkeyDecreaseOpacity = 4;
constexpr UINT kHotkeyIncreaseOpacity = 5;
constexpr UINT kHotkeyDecreaseBlur = 6;
constexpr UINT kHotkeyIncreaseBlur = 7;
constexpr UINT kHotkeyToggleGrayscale = 8;
constexpr UINT kHotkeyToggleTransparent = 9;
constexpr UINT kHotkeyReloadSettings = 10;
constexpr UINT kHotkeyToggleTheme = 11;

constexpr int kControlIdSettings = 1001;
constexpr int kControlIdReload = 1002;
constexpr int kControlIdTabs = 1003;

struct ACCENT_POLICY {
    int AccentState;
    int AccentFlags;
    unsigned int GradientColor;
    int AnimationId;
};

struct WINDOWCOMPOSITIONATTRIBDATA {
    int Attrib;
    PVOID pvData;
    SIZE_T cbData;
};

enum ACCENT_STATE {
    ACCENT_DISABLED = 0,
    ACCENT_ENABLE_GRADIENT = 1,
    ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
    ACCENT_ENABLE_BLURBEHIND = 3,
    ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
};

enum WINDOWCOMPOSITIONATTRIB {
    WCA_ACCENT_POLICY = 19,
};

using SetWindowCompositionAttributeProc = BOOL(WINAPI*)(HWND, WINDOWCOMPOSITIONATTRIBDATA*);

struct TabConfig {
    std::wstring title;
    std::wstring url;
};

struct AppSettings {
    enum class ThemeMode {
        System,
        Light,
        Dark,
    };

    std::vector<TabConfig> tabs;
    BYTE windowAlpha = 230;
    BYTE blurOpacity = 96;
    bool grayscaleEnabled = false;
    bool transparentBackgroundEnabled = true;
    ThemeMode themeMode = ThemeMode::System;
};

struct TabRuntime {
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> webview;
};

std::wstring Utf8ToWide(const std::string& s) {
    if (s.empty()) return L"";
    const int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring out(len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), len);
    return out;
}

std::wstring Trim(const std::wstring& input) {
    const auto begin = input.find_first_not_of(L" \t\r\n");
    if (begin == std::wstring::npos) return L"";
    const auto end = input.find_last_not_of(L" \t\r\n");
    return input.substr(begin, end - begin + 1);
}

std::wstring ToLowerWide(std::wstring value) {
    for (auto& ch : value) {
        if (ch >= L'A' && ch <= L'Z') {
            ch = static_cast<wchar_t>(ch - L'A' + L'a');
        }
    }
    return value;
}

bool IsSystemDarkThemeEnabled() {
    DWORD value = 1;
    DWORD size = sizeof(value);
    const LSTATUS status = RegGetValueW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme",
        RRF_RT_REG_DWORD,
        nullptr,
        &value,
        &size);

    if (status != ERROR_SUCCESS) {
        return false;
    }

    return value == 0;
}

std::wstring Hex32(unsigned long value) {
    wchar_t buffer[16]{};
    wsprintfW(buffer, L"0x%08lX", value);
    return buffer;
}

std::wstring DescribeWin32Error(DWORD errorCode) {
    if (errorCode == 0) {
        return L"No additional OS error details.";
    }

    LPWSTR rawMessage = nullptr;
    const DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
    const DWORD length = FormatMessageW(
        flags,
        nullptr,
        errorCode,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPWSTR>(&rawMessage),
        0,
        nullptr);

    std::wstring message;
    if (length > 0 && rawMessage != nullptr) {
        message.assign(rawMessage, length);
        LocalFree(rawMessage);
        message = Trim(message);
    }

    if (message.empty()) {
        message = L"Unknown Win32 error.";
    }

    return message;
}

std::wstring DescribeHResult(HRESULT hr) {
    if (SUCCEEDED(hr)) {
        return L"Operation succeeded.";
    }

    LPWSTR rawMessage = nullptr;
    const DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
    const DWORD length = FormatMessageW(
        flags,
        nullptr,
        static_cast<DWORD>(hr),
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPWSTR>(&rawMessage),
        0,
        nullptr);

    std::wstring message;
    if (length > 0 && rawMessage != nullptr) {
        message.assign(rawMessage, length);
        LocalFree(rawMessage);
        message = Trim(message);
    }

    if (message.empty()) {
        message = L"Unknown HRESULT.";
    }

    return message;
}

class StealthApp {
public:
    explicit StealthApp(HINSTANCE instance)
        : instance_(instance) {}

    bool Initialize();
    int Run();
    const std::wstring& GetInitializationError() const { return initError_; }

private:
    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    LRESULT HandleMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

    bool CreateMainWindow();
    void CreateChromeControls();
    void LayoutControls();

    void RegisterGlobalHotkeys();
    void UnregisterGlobalHotkeys();
    void HandleHotkey(UINT id);

    void InitializeWebViewEnvironment();
    void CreateWebViewForTab(size_t index);
    void OnWebViewCreated(size_t index, HRESULT result, ICoreWebView2Controller* controller);
    void ConfigureWebView(size_t index);
    void ResizeWebViews();
    void SelectTab(size_t index);

    void LoadSettings();
    void SaveVisualSettings();
    void EnsureSettingsFileExists();
    std::wstring ResolveSettingsPath();
    std::wstring ResolveUserDataFolder();

    void RebuildTabControl();

    void ToggleVisibility();
    void RefreshCurrentTab();
    void AdjustOpacity(int delta);
    void AdjustBlur(int delta);
    void ToggleGrayscale();
    void ToggleTransparentBackground();
    void ApplyStealthModesToAll();
    void ApplyWindowVisuals();
    void ApplyBlurOpacity(BYTE blurOpacity);
    void ApplyTheme();
    void CycleThemeMode();

    void OpenSettingsFile();
    void ReloadSettings();

    std::wstring BuildStealthInjectionScript() const;

private:
    HINSTANCE instance_ = nullptr;
    HWND hwnd_ = nullptr;
    HWND settingsButton_ = nullptr;
    HWND reloadButton_ = nullptr;
    HWND tabControl_ = nullptr;

    AppSettings settings_;
    std::wstring settingsPath_;
    std::wstring userDataFolder_;

    ComPtr<ICoreWebView2Environment> webviewEnvironment_;
    std::vector<TabRuntime> tabRuntimes_;

    RECT webBounds_{};
    size_t selectedTabIndex_ = 0;
    bool isVisible_ = true;
    std::wstring initError_;
    COLORREF backgroundColor_ = RGB(255, 255, 255);
};

bool StealthApp::Initialize() {
    INITCOMMONCONTROLSEX icc{};
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_TAB_CLASSES;
    InitCommonControlsEx(&icc);

    LoadSettings();

    if (!CreateMainWindow()) {
        return false;
    }

    CreateChromeControls();
    LayoutControls();
    RegisterGlobalHotkeys();
    InitializeWebViewEnvironment();

    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
    UpdateWindow(hwnd_);
    SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);

    return true;
}

int StealthApp::Run() {
    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return static_cast<int>(msg.wParam);
}

bool StealthApp::CreateMainWindow() {
    const wchar_t* className = L"StealthAIWindowClass";

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.hInstance = instance_;
    wc.lpfnWndProc = StealthApp::WndProc;
    wc.lpszClassName = className;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = nullptr;

    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        const DWORD error = GetLastError();
        initError_ = L"RegisterClassExW failed (" + Hex32(error) + L"): " + DescribeWin32Error(error);
        return false;
    }

    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_TOPMOST,
        className,
        L"stealthAI",
        WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        900,
        680,
        nullptr,
        nullptr,
        instance_,
        this);

    if (!hwnd_) {
        const DWORD error = GetLastError();
        initError_ = L"CreateWindowExW failed (" + Hex32(error) + L"): " + DescribeWin32Error(error);
        return false;
    }

    ApplyWindowVisuals();
    return true;
}

void StealthApp::CreateChromeControls() {
    tabControl_ = CreateWindowExW(
        0,
        WC_TABCONTROLW,
        L"",
        WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
        8,
        8,
        600,
        28,
        hwnd_,
        reinterpret_cast<HMENU>(kControlIdTabs),
        instance_,
        nullptr);

    settingsButton_ = CreateWindowExW(
        0,
        L"BUTTON",
        L"Settings",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0,
        8,
        88,
        26,
        hwnd_,
        reinterpret_cast<HMENU>(kControlIdSettings),
        instance_,
        nullptr);

    reloadButton_ = CreateWindowExW(
        0,
        L"BUTTON",
        L"Reload",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0,
        8,
        88,
        26,
        hwnd_,
        reinterpret_cast<HMENU>(kControlIdReload),
        instance_,
        nullptr);

    RebuildTabControl();
}

void StealthApp::LayoutControls() {
    RECT client{};
    GetClientRect(hwnd_, &client);

    const int buttonWidth = 88;
    const int buttonHeight = 26;
    const int spacing = 8;

    const int settingsX = client.right - buttonWidth - spacing;
    const int reloadX = settingsX - buttonWidth - spacing;

    SetWindowPos(settingsButton_, nullptr, settingsX, 8, buttonWidth, buttonHeight, SWP_NOZORDER);
    SetWindowPos(reloadButton_, nullptr, reloadX, 8, buttonWidth, buttonHeight, SWP_NOZORDER);

    const int tabWidth = std::max(120, reloadX - spacing - 8);
    SetWindowPos(tabControl_, nullptr, 8, 8, tabWidth, 28, SWP_NOZORDER);

    webBounds_.left = 0;
    webBounds_.top = kTitleBarHeight;
    webBounds_.right = client.right;
    webBounds_.bottom = client.bottom;

    ResizeWebViews();
}

void StealthApp::RegisterGlobalHotkeys() {
    RegisterHotKey(hwnd_, kHotkeyTogglePanel, MOD_CONTROL | MOD_SHIFT, VK_SPACE);
    RegisterHotKey(hwnd_, kHotkeySwitchTab, MOD_CONTROL | MOD_SHIFT, VK_TAB);
    RegisterHotKey(hwnd_, kHotkeyRefreshTab, MOD_CONTROL | MOD_SHIFT, 'R');
    RegisterHotKey(hwnd_, kHotkeyDecreaseOpacity, MOD_CONTROL | MOD_SHIFT, VK_OEM_4);
    RegisterHotKey(hwnd_, kHotkeyIncreaseOpacity, MOD_CONTROL | MOD_SHIFT, VK_OEM_6);
    RegisterHotKey(hwnd_, kHotkeyDecreaseBlur, MOD_CONTROL | MOD_SHIFT, VK_OEM_1);
    RegisterHotKey(hwnd_, kHotkeyIncreaseBlur, MOD_CONTROL | MOD_SHIFT, VK_OEM_7);
    RegisterHotKey(hwnd_, kHotkeyToggleGrayscale, MOD_CONTROL | MOD_SHIFT, 'G');
    RegisterHotKey(hwnd_, kHotkeyToggleTransparent, MOD_CONTROL | MOD_SHIFT, 'T');
    RegisterHotKey(hwnd_, kHotkeyReloadSettings, MOD_CONTROL | MOD_SHIFT, 'L');
    RegisterHotKey(hwnd_, kHotkeyToggleTheme, MOD_CONTROL | MOD_SHIFT, 'M');
}

void StealthApp::UnregisterGlobalHotkeys() {
    UnregisterHotKey(hwnd_, kHotkeyTogglePanel);
    UnregisterHotKey(hwnd_, kHotkeySwitchTab);
    UnregisterHotKey(hwnd_, kHotkeyRefreshTab);
    UnregisterHotKey(hwnd_, kHotkeyDecreaseOpacity);
    UnregisterHotKey(hwnd_, kHotkeyIncreaseOpacity);
    UnregisterHotKey(hwnd_, kHotkeyDecreaseBlur);
    UnregisterHotKey(hwnd_, kHotkeyIncreaseBlur);
    UnregisterHotKey(hwnd_, kHotkeyToggleGrayscale);
    UnregisterHotKey(hwnd_, kHotkeyToggleTransparent);
    UnregisterHotKey(hwnd_, kHotkeyReloadSettings);
    UnregisterHotKey(hwnd_, kHotkeyToggleTheme);
}

void StealthApp::HandleHotkey(UINT id) {
    switch (id) {
        case kHotkeyTogglePanel:
            ToggleVisibility();
            break;
        case kHotkeySwitchTab:
            if (!settings_.tabs.empty()) {
                const size_t next = (selectedTabIndex_ + 1) % settings_.tabs.size();
                SelectTab(next);
            }
            break;
        case kHotkeyRefreshTab:
            RefreshCurrentTab();
            break;
        case kHotkeyDecreaseOpacity:
            AdjustOpacity(-kAlphaStep);
            break;
        case kHotkeyIncreaseOpacity:
            AdjustOpacity(kAlphaStep);
            break;
        case kHotkeyDecreaseBlur:
            AdjustBlur(-kBlurStep);
            break;
        case kHotkeyIncreaseBlur:
            AdjustBlur(kBlurStep);
            break;
        case kHotkeyToggleGrayscale:
            ToggleGrayscale();
            break;
        case kHotkeyToggleTransparent:
            ToggleTransparentBackground();
            break;
        case kHotkeyReloadSettings:
            ReloadSettings();
            break;
        case kHotkeyToggleTheme:
            CycleThemeMode();
            break;
        default:
            break;
    }
}

void StealthApp::InitializeWebViewEnvironment() {
    userDataFolder_ = ResolveUserDataFolder();

    CreateCoreWebView2EnvironmentWithOptions(
        nullptr,
        userDataFolder_.c_str(),
        nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [this](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
                if (FAILED(result) || env == nullptr) {
                    MessageBoxW(hwnd_, L"WebView2 runtime was not found. Please install Microsoft Edge WebView2 Runtime.", L"stealthAI", MB_ICONERROR);
                    return result;
                }
                webviewEnvironment_ = env;
                tabRuntimes_.clear();
                tabRuntimes_.resize(settings_.tabs.size());
                CreateWebViewForTab(0);
                return S_OK;
            })
            .Get());
}

void StealthApp::CreateWebViewForTab(size_t index) {
    if (!webviewEnvironment_ || index >= settings_.tabs.size()) {
        ApplyStealthModesToAll();
        SelectTab(std::min(selectedTabIndex_, settings_.tabs.empty() ? size_t{0} : settings_.tabs.size() - 1));
        return;
    }

    webviewEnvironment_->CreateCoreWebView2Controller(
        hwnd_,
        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [this, index](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT {
                OnWebViewCreated(index, result, controller);
                return S_OK;
            })
            .Get());
}

void StealthApp::OnWebViewCreated(size_t index, HRESULT result, ICoreWebView2Controller* controller) {
    if (FAILED(result) || controller == nullptr || index >= tabRuntimes_.size()) {
        return;
    }

    tabRuntimes_[index].controller = controller;
    controller->get_CoreWebView2(&tabRuntimes_[index].webview);

    ConfigureWebView(index);

    RECT bounds = webBounds_;
    tabRuntimes_[index].controller->put_Bounds(bounds);
    tabRuntimes_[index].controller->put_IsVisible(index == selectedTabIndex_);

    if (tabRuntimes_[index].webview) {
        const std::wstring& url = settings_.tabs[index].url.empty() ? L"https://chatgpt.com" : settings_.tabs[index].url;
        tabRuntimes_[index].webview->Navigate(url.c_str());
    }

    CreateWebViewForTab(index + 1);
}

void StealthApp::ConfigureWebView(size_t index) {
    if (index >= tabRuntimes_.size()) return;
    auto& runtime = tabRuntimes_[index];
    if (!runtime.webview || !runtime.controller) return;

    runtime.webview->AddScriptToExecuteOnDocumentCreated(BuildStealthInjectionScript().c_str(), nullptr);

    runtime.webview->add_NewWindowRequested(
        Callback<ICoreWebView2NewWindowRequestedEventHandler>(
            [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
                LPWSTR raw = nullptr;
                if (SUCCEEDED(args->get_Uri(&raw)) && raw != nullptr) {
                    ShellExecuteW(nullptr, L"open", raw, nullptr, nullptr, SW_SHOWNORMAL);
                }
                CoTaskMemFree(raw);
                args->put_Handled(TRUE);
                return S_OK;
            })
            .Get(),
        nullptr);

    ComPtr<ICoreWebView2Controller2> controller2;
    if (SUCCEEDED(runtime.controller.As(&controller2)) && controller2) {
        COREWEBVIEW2_COLOR color{};
        if (settings_.transparentBackgroundEnabled) {
            color = {0, 0, 0, 0};
        } else {
            color = {17, 17, 17, 255};
        }
        controller2->put_DefaultBackgroundColor(color);
    }
}

void StealthApp::ResizeWebViews() {
    for (auto& runtime : tabRuntimes_) {
        if (runtime.controller) {
            runtime.controller->put_Bounds(webBounds_);
        }
    }
}

void StealthApp::SelectTab(size_t index) {
    if (settings_.tabs.empty()) return;
    selectedTabIndex_ = std::min(index, settings_.tabs.size() - 1);

    for (size_t i = 0; i < tabRuntimes_.size(); ++i) {
        if (tabRuntimes_[i].controller) {
            tabRuntimes_[i].controller->put_IsVisible(i == selectedTabIndex_);
        }
    }

    if (tabControl_) {
        TabCtrl_SetCurSel(tabControl_, static_cast<int>(selectedTabIndex_));
    }
}

void StealthApp::LoadSettings() {
    settingsPath_ = ResolveSettingsPath();
    EnsureSettingsFileExists();

    settings_.tabs.clear();

    int count = GetPrivateProfileIntW(L"Tabs", L"count", 3, settingsPath_.c_str());
    count = std::clamp(count, 1, kMaxTabs);

    for (int i = 1; i <= count; ++i) {
        wchar_t titleKey[32]{};
        wchar_t urlKey[32]{};
        wsprintfW(titleKey, L"title%d", i);
        wsprintfW(urlKey, L"url%d", i);

        wchar_t titleBuffer[256]{};
        wchar_t urlBuffer[1024]{};

        GetPrivateProfileStringW(L"Tabs", titleKey, L"", titleBuffer, 256, settingsPath_.c_str());
        GetPrivateProfileStringW(L"Tabs", urlKey, L"", urlBuffer, 1024, settingsPath_.c_str());

        std::wstring title = Trim(titleBuffer);
        if (title.empty()) {
            title = L"Tab " + std::to_wstring(i);
        }

        std::wstring url = Trim(urlBuffer);
        settings_.tabs.push_back({title, url});
    }

    if (settings_.tabs.empty()) {
        settings_.tabs.push_back({L"ChatGPT", L"https://chatgpt.com"});
    }

    const int alpha = GetPrivateProfileIntW(L"Visual", L"opacity", 230, settingsPath_.c_str());
    settings_.windowAlpha = static_cast<BYTE>(std::clamp(alpha, static_cast<int>(kMinAlpha), static_cast<int>(kMaxAlpha)));

    const int blur = GetPrivateProfileIntW(L"Visual", L"blur", 96, settingsPath_.c_str());
    settings_.blurOpacity = static_cast<BYTE>(std::clamp(blur, 0, static_cast<int>(kMaxBlur)));

    settings_.grayscaleEnabled = GetPrivateProfileIntW(L"Visual", L"grayscale", 0, settingsPath_.c_str()) != 0;
    settings_.transparentBackgroundEnabled = GetPrivateProfileIntW(L"Visual", L"transparent_bg", 1, settingsPath_.c_str()) != 0;

    wchar_t themeMode[32]{};
    GetPrivateProfileStringW(L"Visual", L"theme_mode", L"system", themeMode, 32, settingsPath_.c_str());
    const std::wstring mode = ToLowerWide(Trim(themeMode));
    if (mode == L"dark") {
        settings_.themeMode = AppSettings::ThemeMode::Dark;
    } else if (mode == L"light") {
        settings_.themeMode = AppSettings::ThemeMode::Light;
    } else {
        settings_.themeMode = AppSettings::ThemeMode::System;
    }

    if (selectedTabIndex_ >= settings_.tabs.size()) {
        selectedTabIndex_ = settings_.tabs.size() - 1;
    }
}

void StealthApp::SaveVisualSettings() {
    wchar_t value[32]{};

    wsprintfW(value, L"%d", static_cast<int>(settings_.windowAlpha));
    WritePrivateProfileStringW(L"Visual", L"opacity", value, settingsPath_.c_str());

    wsprintfW(value, L"%d", static_cast<int>(settings_.blurOpacity));
    WritePrivateProfileStringW(L"Visual", L"blur", value, settingsPath_.c_str());

    WritePrivateProfileStringW(L"Visual", L"grayscale", settings_.grayscaleEnabled ? L"1" : L"0", settingsPath_.c_str());
    WritePrivateProfileStringW(L"Visual", L"transparent_bg", settings_.transparentBackgroundEnabled ? L"1" : L"0", settingsPath_.c_str());

    const wchar_t* mode = L"system";
    if (settings_.themeMode == AppSettings::ThemeMode::Light) {
        mode = L"light";
    } else if (settings_.themeMode == AppSettings::ThemeMode::Dark) {
        mode = L"dark";
    }
    WritePrivateProfileStringW(L"Visual", L"theme_mode", mode, settingsPath_.c_str());
}

void StealthApp::EnsureSettingsFileExists() {
    if (PathFileExistsW(settingsPath_.c_str())) {
        return;
    }

    const std::wstring defaultContent =
        L"; stealthAI Windows settings\n"
        L"; Edit tabs and URLs, then click Reload in the app (or press Ctrl+Shift+L).\n"
        L"[Tabs]\n"
        L"count=3\n"
        L"title1=ChatGPT\n"
        L"url1=https://chatgpt.com\n"
        L"title2=Claude\n"
        L"url2=https://claude.ai\n"
        L"title3=Gemini\n"
        L"url3=https://gemini.google.com\n"
        L"\n"
        L"[Visual]\n"
        L"opacity=230\n"
        L"blur=96\n"
        L"grayscale=0\n"
        L"transparent_bg=1\n"
        L"theme_mode=system\n";

    std::wofstream file(settingsPath_);
    file << defaultContent;
}

std::wstring StealthApp::ResolveSettingsPath() {
    wchar_t appData[MAX_PATH]{};
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, appData))) {
        return L"settings.ini";
    }

    std::filesystem::path dir = std::filesystem::path(appData) / L"StealthAI";
    std::filesystem::create_directories(dir);
    return (dir / L"settings.ini").wstring();
}

std::wstring StealthApp::ResolveUserDataFolder() {
    wchar_t localAppData[MAX_PATH]{};
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, localAppData))) {
        return L"";
    }

    std::filesystem::path dir = std::filesystem::path(localAppData) / L"StealthAI" / L"WebView2";
    std::filesystem::create_directories(dir);
    return dir.wstring();
}

void StealthApp::RebuildTabControl() {
    if (!tabControl_) return;

    TabCtrl_DeleteAllItems(tabControl_);

    TCITEMW item{};
    item.mask = TCIF_TEXT;

    for (size_t i = 0; i < settings_.tabs.size(); ++i) {
        item.pszText = const_cast<LPWSTR>(settings_.tabs[i].title.c_str());
        TabCtrl_InsertItem(tabControl_, static_cast<int>(i), &item);
    }

    TabCtrl_SetCurSel(tabControl_, static_cast<int>(selectedTabIndex_));
}

void StealthApp::ToggleVisibility() {
    isVisible_ = !isVisible_;
    if (isVisible_) {
        ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
        SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
    } else {
        ShowWindow(hwnd_, SW_HIDE);
    }
}

void StealthApp::RefreshCurrentTab() {
    if (selectedTabIndex_ < tabRuntimes_.size() && tabRuntimes_[selectedTabIndex_].webview) {
        tabRuntimes_[selectedTabIndex_].webview->Reload();
    }
}

void StealthApp::AdjustOpacity(int delta) {
    int next = static_cast<int>(settings_.windowAlpha) + delta;
    next = std::clamp(next, static_cast<int>(kMinAlpha), static_cast<int>(kMaxAlpha));
    settings_.windowAlpha = static_cast<BYTE>(next);
    ApplyWindowVisuals();
    SaveVisualSettings();
}

void StealthApp::AdjustBlur(int delta) {
    int next = static_cast<int>(settings_.blurOpacity) + delta;
    next = std::clamp(next, 0, static_cast<int>(kMaxBlur));
    settings_.blurOpacity = static_cast<BYTE>(next);
    ApplyBlurOpacity(settings_.blurOpacity);
    SaveVisualSettings();
}

void StealthApp::ToggleGrayscale() {
    settings_.grayscaleEnabled = !settings_.grayscaleEnabled;
    ApplyStealthModesToAll();
    SaveVisualSettings();
}

void StealthApp::ToggleTransparentBackground() {
    settings_.transparentBackgroundEnabled = !settings_.transparentBackgroundEnabled;

    for (auto& runtime : tabRuntimes_) {
        if (!runtime.controller) continue;
        ComPtr<ICoreWebView2Controller2> controller2;
        if (SUCCEEDED(runtime.controller.As(&controller2)) && controller2) {
            COREWEBVIEW2_COLOR color{};
            if (settings_.transparentBackgroundEnabled) {
                color = {0, 0, 0, 0};
            } else {
                color = {17, 17, 17, 255};
            }
            controller2->put_DefaultBackgroundColor(color);
        }
    }

    ApplyStealthModesToAll();
    SaveVisualSettings();
}

void StealthApp::ApplyStealthModesToAll() {
    const wchar_t* grayscale = settings_.grayscaleEnabled ? L"true" : L"false";
    const wchar_t* transparent = settings_.transparentBackgroundEnabled ? L"true" : L"false";

    std::wstring modeScript = L"window.__stealthAISetMode && window.__stealthAISetMode(";
    modeScript += grayscale;
    modeScript += L",";
    modeScript += transparent;
    modeScript += L");";

    for (auto& runtime : tabRuntimes_) {
        if (runtime.webview) {
            runtime.webview->ExecuteScript(modeScript.c_str(), nullptr);
        }
    }
}

void StealthApp::ApplyWindowVisuals() {
    ApplyTheme();
    SetLayeredWindowAttributes(hwnd_, 0, settings_.windowAlpha, LWA_ALPHA);
    ApplyBlurOpacity(settings_.blurOpacity);
}

void StealthApp::ApplyTheme() {
    bool useDark = false;
    switch (settings_.themeMode) {
        case AppSettings::ThemeMode::Dark:
            useDark = true;
            break;
        case AppSettings::ThemeMode::Light:
            useDark = false;
            break;
        case AppSettings::ThemeMode::System:
            useDark = IsSystemDarkThemeEnabled();
            break;
    }

    const BOOL darkFlag = useDark ? TRUE : FALSE;
    constexpr DWORD DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    DwmSetWindowAttribute(hwnd_, DWMWA_USE_IMMERSIVE_DARK_MODE, &darkFlag, sizeof(darkFlag));

    if (tabControl_) {
        SetWindowTheme(tabControl_, useDark ? L"DarkMode_Explorer" : nullptr, nullptr);
    }
    if (settingsButton_) {
        SetWindowTheme(settingsButton_, useDark ? L"DarkMode_Explorer" : nullptr, nullptr);
    }
    if (reloadButton_) {
        SetWindowTheme(reloadButton_, useDark ? L"DarkMode_Explorer" : nullptr, nullptr);
    }

    backgroundColor_ = useDark ? RGB(28, 28, 30) : GetSysColor(COLOR_WINDOW);
    InvalidateRect(hwnd_, nullptr, TRUE);
}

void StealthApp::CycleThemeMode() {
    switch (settings_.themeMode) {
        case AppSettings::ThemeMode::System:
            settings_.themeMode = AppSettings::ThemeMode::Light;
            break;
        case AppSettings::ThemeMode::Light:
            settings_.themeMode = AppSettings::ThemeMode::Dark;
            break;
        case AppSettings::ThemeMode::Dark:
            settings_.themeMode = AppSettings::ThemeMode::System;
            break;
    }

    ApplyTheme();
    SaveVisualSettings();
}

void StealthApp::ApplyBlurOpacity(BYTE blurOpacity) {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (!user32) return;

    auto setWindowCompositionAttribute = reinterpret_cast<SetWindowCompositionAttributeProc>(
        GetProcAddress(user32, "SetWindowCompositionAttribute"));

    if (!setWindowCompositionAttribute) {
        DWM_BLURBEHIND bb{};
        bb.dwFlags = DWM_BB_ENABLE;
        bb.fEnable = blurOpacity > 0;
        DwmEnableBlurBehindWindow(hwnd_, &bb);
        return;
    }

    ACCENT_POLICY policy{};
    policy.AccentState = blurOpacity == 0 ? ACCENT_DISABLED : ACCENT_ENABLE_ACRYLICBLURBEHIND;
    policy.AccentFlags = 2;
    policy.GradientColor = (static_cast<unsigned int>(blurOpacity) << 24) | 0x101010;

    WINDOWCOMPOSITIONATTRIBDATA data{};
    data.Attrib = WCA_ACCENT_POLICY;
    data.pvData = &policy;
    data.cbData = sizeof(policy);

    setWindowCompositionAttribute(hwnd_, &data);
}

void StealthApp::OpenSettingsFile() {
    ShellExecuteW(hwnd_, L"open", L"notepad.exe", settingsPath_.c_str(), nullptr, SW_SHOWNORMAL);
    MessageBoxW(
        hwnd_,
        L"Edit and save the file, then click Reload (or press Ctrl+Shift+L).",
        L"stealthAI Settings",
        MB_OK | MB_ICONINFORMATION);
}

void StealthApp::ReloadSettings() {
    LoadSettings();

    for (auto& runtime : tabRuntimes_) {
        if (runtime.controller) {
            runtime.controller->Close();
        }
    }

    tabRuntimes_.clear();
    RebuildTabControl();
    ApplyWindowVisuals();

    tabRuntimes_.resize(settings_.tabs.size());
    CreateWebViewForTab(0);
}

std::wstring StealthApp::BuildStealthInjectionScript() const {
    const char* source = R"JS(
(() => {
    if (window.__stealthAIInjected) return;
    window.__stealthAIInjected = true;

    const state = {
        grayscale: false,
        transparentBg: true
    };

    const injectBaseStyles = () => {
        const style = document.createElement('style');
        style.id = 'stealthai-style';
        style.textContent = `
            *, *::before, *::after {
                animation: none !important;
                transition-property: none !important;
                transition-duration: 0s !important;
                transition-delay: 0s !important;
                scroll-behavior: auto !important;
            }

            html, body,
            #root, #__next, #app, #main, #content,
            [data-reactroot], [id="__nuxt"],
            body > div, body > main, body > section {
                background: transparent !important;
                background-color: transparent !important;
                background-image: none !important;
            }
        `;
        document.documentElement.appendChild(style);
    };

    const applyState = () => {
        const dynamicStyle = document.createElement('style');
        const pageBg = state.transparentBg ? 'transparent' : '#111';
        dynamicStyle.textContent = `
            html {
                filter: ${state.grayscale ? 'grayscale(1)' : 'none'} !important;
            }
            html, body,
            #root, #__next, #app, #main, #content,
            [data-reactroot], [id="__nuxt"],
            body > div, body > main, body > section {
                background: ${pageBg} !important;
                background-color: ${pageBg} !important;
                background-image: ${state.transparentBg ? 'none' : 'initial'} !important;
            }
        `;

        const existing = document.getElementById('stealthai-dynamic-style');
        if (existing) {
            existing.remove();
        }

        dynamicStyle.id = 'stealthai-dynamic-style';
        document.documentElement.appendChild(dynamicStyle);
    };

    window.__stealthAISetMode = (grayscale, transparentBg) => {
        state.grayscale = !!grayscale;
        state.transparentBg = !!transparentBg;
        applyState();
    };

    if (document.documentElement) {
        injectBaseStyles();
        applyState();
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            injectBaseStyles();
            applyState();
        }, { once: true });
    }
})();
)JS";

    return Utf8ToWide(source);
}

LRESULT CALLBACK StealthApp::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    StealthApp* app = nullptr;

    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lParam);
        app = reinterpret_cast<StealthApp*>(cs->lpCreateParams);
        if (app) {
            app->hwnd_ = hwnd;
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(app));
        }
    } else {
        app = reinterpret_cast<StealthApp*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }

    if (app) {
        return app->HandleMessage(hwnd, msg, wParam, lParam);
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT StealthApp::HandleMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_COMMAND: {
            const int controlId = LOWORD(wParam);
            if (controlId == kControlIdSettings) {
                OpenSettingsFile();
                return 0;
            }
            if (controlId == kControlIdReload) {
                ReloadSettings();
                return 0;
            }
            break;
        }
        case WM_NOTIFY: {
            const auto* nm = reinterpret_cast<NMHDR*>(lParam);
            if (nm->idFrom == kControlIdTabs && nm->code == TCN_SELCHANGE) {
                const int idx = TabCtrl_GetCurSel(tabControl_);
                if (idx >= 0) {
                    SelectTab(static_cast<size_t>(idx));
                }
                return 0;
            }
            break;
        }
        case WM_SIZE:
            LayoutControls();
            return 0;
        case WM_ERASEBKGND: {
            HDC dc = reinterpret_cast<HDC>(wParam);
            RECT rect{};
            GetClientRect(hwnd, &rect);
            SetDCBrushColor(dc, backgroundColor_);
            FillRect(dc, &rect, reinterpret_cast<HBRUSH>(GetStockObject(DC_BRUSH)));
            return 1;
        }
        case WM_HOTKEY:
            HandleHotkey(static_cast<UINT>(wParam));
            return 0;
        case WM_NCHITTEST: {
            const LRESULT hit = DefWindowProcW(hwnd, msg, wParam, lParam);
            if (hit == HTCLIENT) {
                POINT cursor{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
                ScreenToClient(hwnd, &cursor);

                RECT client{};
                GetClientRect(hwnd, &client);
                const int border = 8;

                if (cursor.x < border && cursor.y < border) return HTTOPLEFT;
                if (cursor.x > client.right - border && cursor.y < border) return HTTOPRIGHT;
                if (cursor.x < border && cursor.y > client.bottom - border) return HTBOTTOMLEFT;
                if (cursor.x > client.right - border && cursor.y > client.bottom - border) return HTBOTTOMRIGHT;
                if (cursor.y < border) return HTTOP;
                if (cursor.y > client.bottom - border) return HTBOTTOM;
                if (cursor.x < border) return HTLEFT;
                if (cursor.x > client.right - border) return HTRIGHT;

                if (cursor.y <= kTitleBarHeight) {
                    HWND child = ChildWindowFromPointEx(hwnd, cursor, CWP_SKIPINVISIBLE);
                    if (child == hwnd) {
                        return HTCAPTION;
                    }
                }
            }
            return hit;
        }
        case WM_DESTROY:
            UnregisterGlobalHotkeys();
            PostQuitMessage(0);
            return 0;
        default:
            break;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, PWSTR, int) {
    const HRESULT coInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(coInit)) {
        std::wstring message = L"CoInitializeEx failed (" + Hex32(static_cast<unsigned long>(coInit)) + L"): " + DescribeHResult(coInit);
        MessageBoxW(nullptr, message.c_str(), L"stealthAI", MB_ICONERROR);
        return 1;
    }

    auto app = std::make_unique<StealthApp>(hInstance);
    if (!app->Initialize()) {
        std::wstring message = app->GetInitializationError();
        if (message.empty()) {
            message = L"Failed to initialize stealthAI due to an unknown startup error.";
        }
        MessageBoxW(nullptr, message.c_str(), L"stealthAI", MB_ICONERROR);
        CoUninitialize();
        return 1;
    }

    const int code = app->Run();
    CoUninitialize();
    return code;
}
