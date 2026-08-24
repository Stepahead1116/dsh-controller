import Cocoa

// DSH Controller — 菜单栏轻量控制器
// 通过 launchctl 管理 com.dsh.web 服务：启动/关闭/重启

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let label = "com.dsh.web"

    var guiDomain: String { "gui/\(getuid())" }
    var serviceTarget: String { "\(guiDomain)/\(label)" }
    var plistPath: String { "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist" }

    let menu = NSMenu()
    let statusMenuItem = NSMenuItem()
    let startItem = NSMenuItem(title: "启动 dsh 服务", action: #selector(startService), keyEquivalent: "s")
    let stopItem = NSMenuItem(title: "关闭 dsh 服务", action: #selector(stopService), keyEquivalent: "x")
    let restartItem = NSMenuItem(title: "重启 dsh 服务", action: #selector(restartService), keyEquivalent: "r")
    let updateItem = NSMenuItem(title: "检查更新（当前 …）", action: #selector(checkUpdate), keyEquivalent: "u")
    let quitItem = NSMenuItem(title: "退出 DSH Controller", action: #selector(quit), keyEquivalent: "q")
    var timer: Timer?
    var currentVersion: String = "?"
    var updateBusy: Bool = false

    // npm / dsh 的安装位置（GUI 进程默认 PATH 不含 homebrew，故用绝对路径）
    let npmBin = "/opt/homebrew/bin/npm"
    let dshBin = "/opt/homebrew/bin/dsh"

    // DeepSeek 图标矢量路径（来自 simpleicons），通过填充色区分状态
    let logoPath = "M23.748 4.651c-.254-.124-.364.113-.512.233-.051.04-.094.09-.137.137-.372.397-.806.657-1.373.626-.829-.046-1.537.214-2.163.848-.133-.782-.575-1.248-1.247-1.548-.352-.155-.708-.311-.955-.65-.172-.24-.219-.509-.305-.774-.055-.16-.11-.323-.293-.35-.2-.031-.278.136-.356.276-.313.572-.434 1.202-.422 1.84.027 1.436.633 2.58 1.838 3.393.137.094.172.187.129.323-.082.28-.18.553-.266.833-.055.179-.137.218-.328.14a5.5 5.5 0 0 1-1.737-1.179c-.857-.828-1.631-1.743-2.597-2.46a12 12 0 0 0-.689-.47c-.985-.957.13-1.743.387-1.836.27-.098.094-.433-.778-.428-.872.003-1.67.295-2.687.685a3 3 0 0 1-.465.136 9.6 9.6 0 0 0-2.883-.101c-1.885.21-3.39 1.1-4.497 2.622C.082 8.776-.231 10.854.152 13.02c.403 2.284 1.568 4.175 3.36 5.653 1.857 1.533 3.997 2.284 6.438 2.14 1.482-.085 3.132-.284 4.994-1.86.47.234.962.328 1.78.398.629.058 1.235-.031 1.705-.129.735-.155.684-.836.418-.961-2.155-1.004-1.682-.595-2.112-.926 1.095-1.295 2.768-3.598 3.284-6.733.05-.346.115-.834.108-1.114-.004-.171.035-.238.23-.257a4.2 4.2 0 0 0 1.545-.475c1.397-.763 1.96-2.016 2.093-3.517.02-.23-.004-.467-.247-.588M11.58 18.168c-2.088-1.642-3.101-2.183-3.52-2.16-.39.024-.32.472-.234.763.09.288.207.487.371.74.114.167.192.416-.113.603-.673.416-1.842-.14-1.897-.168-1.361-.801-2.5-1.86-3.301-3.306-.775-1.393-1.225-2.888-1.299-4.482-.02-.385.094-.522.477-.592a4.7 4.7 0 0 1 1.53-.038c2.131.311 3.946 1.264 5.467 2.774.868.86 1.525 1.887 2.202 2.89.72 1.066 1.494 2.082 2.48 2.915.348.291.626.513.892.677-.802.09-2.14.109-3.055-.615zm1.001-6.44a.306.306 0 0 1 .415-.287.3.3 0 0 1 .113.074.3.3 0 0 1 .086.214c0 .17-.136.307-.308.307a.303.303 0 0 1-.306-.307m3.11 1.596c-.2.081-.4.151-.591.16a1.25 1.25 0 0 1-.798-.254c-.274-.23-.47-.358-.551-.758a1.7 1.7 0 0 1 .015-.588c.07-.327-.007-.537-.238-.727-.188-.156-.426-.199-.689-.199a.6.6 0 0 1-.254-.078.253.253 0 0 1-.114-.358 1 1 0 0 1 .192-.21c.356-.202.767-.136 1.146.016.352.144.618.408 1.001.782.392.451.462.576.685.915.176.264.336.536.446.848.066.194-.02.353-.25.45"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // 不显示 Dock 图标，仅菜单栏
        let button = statusItem.button!
        button.image = logoImage(color: "#8E8E93")
        button.toolTip = "DSH Controller"
        menu.delegate = self
        buildMenu()
        statusItem.menu = menu
        refresh()
        // 每 5 秒刷新一次状态，开销极小
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // 启动后异步取一次已安装版本号，更新检查更新按钮标题
        refreshInstalledVersion()
    }

    func buildMenu() {
        statusMenuItem.isEnabled = false
        updateItem.target = self
        for item in [startItem, stopItem, restartItem, quitItem] { item.target = self }
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(restartItem)
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    // MARK: - 状态查询

    /// 返回 (是否运行中, PID)
    func status() -> (running: Bool, pid: String?) {
        // launchctl list 仅列出已加载的服务；输出行格式：PID<TAB>Status<TAB>Label
        let (out, _) = shell("launchctl list | grep -w '\(label)'")
        let line = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return (false, nil) }
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = fields.first else { return (false, nil) }
        if first == "-" { return (false, nil) }
        return (true, first)
    }

    func refresh() {
        let (running, pid) = status()
        statusItem.button?.image = logoImage(color: running ? "#30D158" : "#8E8E93")
        statusMenuItem.title = running ? "dsh 运行中（PID \(pid ?? "?")）" : "dsh 已停止"
        startItem.isEnabled = !running
        stopItem.isEnabled = running
        restartItem.isEnabled = running
    }

    // MARK: - 服务操作

    @objc func startService() {
        if status().running { refresh(); return }
        // bootstrap 会加载并（RunAtLoad=true）启动服务；若已加载会报错，可忽略
        _ = shell("launchctl bootstrap '\(guiDomain)' '\(plistPath)' 2>&1")
        // 兜底：若已加载但未运行，强制拉起
        _ = shell("launchctl kickstart '\(serviceTarget)' 2>&1")
        refresh()
    }

    @objc func stopService() {
        // bootout 卸载服务，KeepAlive 不再生效
        _ = shell("launchctl bootout '\(serviceTarget)' 2>&1")
        refresh()
    }

    @objc func restartService() {
        if status().running {
            _ = shell("launchctl kickstart -k '\(serviceTarget)' 2>&1")
        } else {
            _ = shell("launchctl bootstrap '\(guiDomain)' '\(plistPath)' 2>&1")
            _ = shell("launchctl kickstart '\(serviceTarget)' 2>&1")
        }
        refresh()
    }

    @objc func quit() {
        timer?.invalidate()
        NSApp.terminate(nil)
    }

    // MARK: - 更新检查

    /// 已安装的 dsh 版本号
    func installedVersion() -> String {
        let v = shell("\(dshBin) --version 2>/dev/null").out.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "?" : v
    }

    /// 刷新“检查更新”按钮标题里的版本号（非阻塞）
    func refreshInstalledVersion() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let v = self.installedVersion()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.updateBusy else { return }
                self.currentVersion = v
                self.updateItem.title = "检查更新（当前 \(v)）"
            }
        }
    }

    @objc func checkUpdate() {
        guard !updateBusy else { return }
        updateBusy = true
        updateItem.title = "检查更新中…"
        updateItem.isEnabled = false
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let installed = self.installedVersion()
            let latest = self.shell("HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 \(self.npmBin) view @deepseek-ai/dsh version 2>/dev/null")
                .out.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentVersion = installed
                if latest.isEmpty {
                    self.updateItem.title = "检查更新（当前 \(installed)）— 查询失败"
                    self.finishUpdate()
                } else if latest == installed {
                    self.updateItem.title = "已是最新（\(installed)）"
                    self.finishUpdate()
                } else {
                    self.updateItem.title = "发现新版本 \(latest)，升级中…"
                    self.runUpgrade(latest: latest)
                }
            }
        }
    }

    /// 执行 npm 全局升级并重启 dsh 服务
    func runUpgrade(latest: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let allowScripts = "--allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs"
            let cmd = "HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 \(self.npmBin) install -g \(allowScripts) @deepseek-ai/dsh@latest 2>&1"
            _ = self.shell(cmd)
            // 升级完成后重启服务以加载新版本
            _ = self.shell("launchctl kickstart -k '\(self.serviceTarget)' 2>&1")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let newVer = self.installedVersion()
                self.currentVersion = newVer == "?" ? latest : newVer
                self.updateItem.title = "已升级到 \(self.currentVersion)"
                self.finishUpdate()
            }
        }
    }

    private func finishUpdate() {
        updateBusy = false
        updateItem.isEnabled = true
        refresh()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()  // 打开菜单时即时刷新
        if !updateBusy {
            updateItem.title = "检查更新（当前 \(currentVersion)）"
        }
    }

    // MARK: - 工具

    /// 运行 shell 命令，返回 (合并输出, 退出码)
    @discardableResult
    func shell(_ cmd: String) -> (out: String, code: Int) {
        let p = Process()
        p.launchPath = "/bin/zsh"
        p.arguments = ["-c", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return ("", -1)
        }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", Int(p.terminationStatus))
    }

    /// 用给定填充色生成 DeepSeek 图标（非 template，保留颜色）
    func logoImage(color: String) -> NSImage {
        let svg = "<svg fill=\"\(color)\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\"><path d=\"\(logoPath)\"/></svg>"
        guard let data = svg.data(using: .utf8), let img = NSImage(data: data) else {
            // 兜底：返回空图，避免菜单栏图标消失
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = false
        return img
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
