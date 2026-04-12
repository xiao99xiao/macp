import ArgumentParser

@main
struct Macp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macp",
        abstract: "Mac App Control Protocol — operate and debug macOS apps from the command line.",
        subcommands: [
            CheckAccess.self,
            ListApps.self,
            LaunchApp.self,
            ActivateApp.self,
            QuitApp.self,
            WindowList.self,
            FocusWindow.self,
            UITree.self,
            ReadElement.self,
            WaitFor.self,
            Action.self,
            Menu.self,
            Click.self,
            Drag.self,
            Scroll.self,
            MoveMouse.self,
            TypeText.self,
            KeyPress.self,
            Clipboard.self,
            Screenshot.self,
            InstallSkill.self,
        ]
    )
}
