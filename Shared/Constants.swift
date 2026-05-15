import Foundation

enum Constants {
    static let appGroupID = "group.com.rightmenu.master"
    static let configKey = "menu_config"
    static let templatesKey = "custom_templates"
    static let enabledActionsKey = "enabled_actions"

    static let defaultTemplates: [FileTemplate] = [
        FileTemplate(name: "Plain Text", ext: "txt", content: ""),
        FileTemplate(name: "Markdown", ext: "md", content: "# \n\n"),
        FileTemplate(name: "Swift File", ext: "swift", content: "import Foundation\n\n"),
        FileTemplate(name: "Python File", ext: "py", content: "#!/usr/bin/env python3\n\n\ndef main():\n    pass\n\n\nif __name__ == \"__main__\":\n    main()\n"),
        FileTemplate(name: "JavaScript File", ext: "js", content: "#!/usr/bin/env node\n\n"),
        FileTemplate(name: "Shell Script", ext: "sh", content: "#!/bin/bash\n\nset -euo pipefail\n\n"),
    ]
}
