#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/Common.ps1
    . $PSScriptRoot/../PSCMake/Common/Diagnostics.ps1
}

Describe 'ParseDiagnosticLine' {
    It 'Parses an MSVC warning with line and column' {
        $D = ParseDiagnosticLine 'C:\src\a b\file.cpp(12,5): warning C4100: ''x'': unreferenced parameter'
        $D.Severity | Should -Be 'Warning'
        $D.Path | Should -Be 'C:\src\a b\file.cpp'
        $D.Line | Should -Be 12
        $D.Column | Should -Be 5
        $D.Code | Should -Be 'C4100'
        $D.Message | Should -Be '''x'': unreferenced parameter'
    }
    It 'Parses an MSVC error with no column, defaulting it to 1' {
        $D = ParseDiagnosticLine 'file.cpp(7) : error C2065: ''y'': undeclared identifier'
        $D.Severity | Should -Be 'Error'
        $D.Line | Should -Be 7
        $D.Column | Should -Be 1
    }
    It 'Parses a clang-cl diagnostic (MSVC shape, no code)' {
        $D = ParseDiagnosticLine 'C:\src\file.cpp(3,9): error: use of undeclared identifier ''z'''
        $D.Severity | Should -Be 'Error'
        $D.Line | Should -Be 3
        $D.Column | Should -Be 9
        $D.Code | Should -Be ''
    }
    It 'Parses a clang diagnostic with a drive letter' {
        $D = ParseDiagnosticLine 'C:\src\file.cpp:10:20: warning: unused variable ''v'' [-Wunused-variable]'
        $D.Severity | Should -Be 'Warning'
        $D.Path | Should -Be 'C:\src\file.cpp'
        $D.Line | Should -Be 10
        $D.Column | Should -Be 20
    }
    It 'Parses a POSIX-style clang note' {
        $D = ParseDiagnosticLine '/src/file.cpp:4:1: note: declared here' -Style Clang
        $D.Severity | Should -Be 'Note'
        $D.Path | Should -Be '/src/file.cpp'
    }
    It 'Tolerates a leading Ninja progress prefix' {
        $D = ParseDiagnosticLine '[3/10] file.cpp(1,1): error C1234: boom'
        $D.Path | Should -Be 'file.cpp'
    }
    It 'Reports the location span' {
        $Line = '  file.cpp(12,5): warning C4100: msg'
        $D = ParseDiagnosticLine $Line
        $Line.Substring($D.LocationStart, $D.LocationLength) | Should -Be 'file.cpp(12,5)'
    }
    It 'Classifies a linker error with no location' {
        $D = ParseDiagnosticLine 'LINK : fatal error LNK1181: cannot open input file ''x.lib'''
        $D.Severity | Should -Be 'Error'
        $D.Path | Should -BeNullOrEmpty
        $D.Code | Should -Be 'LNK1181'
    }
    It 'Classifies a bare "error:" line' {
        (ParseDiagnosticLine 'lld-link: error: undefined symbol: foo').Severity | Should -Be 'Error'
    }
    It 'Ignores ordinary output' -ForEach @(
        '[1/5] Building CXX object a.obj'
        'Configuration  : Debug'
        'Build started...'
        ''
    ) {
        ParseDiagnosticLine $_ | Should -BeNullOrEmpty
    }
}

Describe 'GetDiagnosticUri' {
    It 'Builds a VS Code URI' {
        GetDiagnosticUri 'VSCode' 'C:\src\a b\file.cpp' 12 5 | Should -Be 'vscode://file/C:/src/a%20b/file.cpp:12:5'
    }
    It 'Builds a Visual Studio URI' {
        GetDiagnosticUri 'VisualStudio' 'C:\src\file.cpp' 12 5 |
            Should -Be 'pscmake-vs://open?path=C%3A%5Csrc%5Cfile.cpp&line=12&col=5'
    }
    It 'Builds a plain file URI' {
        GetDiagnosticUri 'File' 'C:\src\file.cpp' 12 5 | Should -Be 'file:///C:/src/file.cpp'
    }
}

Describe 'FormatDiagnosticLine' {
    BeforeAll {
        $script:Dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'src')
        $script:File = Join-Path $Dir 'file.cpp'
        Set-Content -LiteralPath $File -Value 'int x;'
    }
    BeforeEach {
        Mock IsVirtualTerminalProcessingEnabled { $true }
    }
    It 'Colors by severity and links an existing file' {
        $Line = "file.cpp(1,2): warning C4100: msg"
        $D = ParseDiagnosticLine $Line
        $Out = FormatDiagnosticLine $Line $D $Dir 'VSCode'
        $Out.Contains("`e[38;2;229;192;123m") | Should -BeTrue
        $Out | Should -Match ([regex]::Escape("`e]8;;vscode://file/"))
        $Out | Should -Match ([regex]::Escape(":1:2`e\file.cpp(1,2)`e]8;;`e\"))
        $Out.EndsWith("`e[39m") | Should -BeTrue
    }
    It 'Colors but does not link a missing file' {
        $Line = "missing.cpp(1,2): error C1: msg"
        $Out = FormatDiagnosticLine $Line (ParseDiagnosticLine $Line) $Dir 'VSCode'
        $Out.Contains("`e[38;2;255;085;085m") | Should -BeTrue
        $Out.Contains("`e]8;;") | Should -BeFalse
    }
    It 'Colors a diagnostic with no location' {
        $Line = 'LINK : fatal error LNK1181: x'
        $Out = FormatDiagnosticLine $Line (ParseDiagnosticLine $Line) $Dir 'VSCode'
        $Out.Contains('LINK : fatal error LNK1181: x') | Should -BeTrue
        $Out.Contains("`e]8;;") | Should -BeFalse
    }
}

Describe 'WriteAugmentedOutput' {
    BeforeEach {
        Mock IsVirtualTerminalProcessingEnabled { $true }
    }
    It 'Passes ordinary lines and error records through as strings' {
        $Record = [System.Management.Automation.ErrorRecord]::new([Exception]::new('from stderr'), 'id', 'NotSpecified', $null)
        $Out = 'plain', $Record | WriteAugmentedOutput
        $Out | Should -Be @('plain', 'from stderr')
    }
    It 'Leaves lines that already contain escape sequences alone' {
        $Line = "`e[31mfile.cpp(1,1): error C1: x`e[0m"
        $Line | WriteAugmentedOutput | Should -Be $Line
    }
    It 'Augments diagnostics' {
        ('file.cpp(1,1): error C1: x' | WriteAugmentedOutput).StartsWith("`e[38;2;") | Should -BeTrue
    }
    It 'Hides Ninja step lines and reports progress when given an activity' {
        Mock Write-Progress {}
        # Repaints are throttled to one per 100ms, so the second step arrives after a delay.
        $Out = '[1/4] Building CXX object a.obj', 'warn.txt', '[3/4] Linking CXX executable a.exe' |
            ForEach-Object { if ($_ -like '`[3*') { Start-Sleep -Milliseconds 150 }; $_ } |
            WriteAugmentedOutput -ProgressActivity 'Building'
        $Out | Should -Be @('warn.txt')
        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $PercentComplete -eq 75 -and $Activity -eq 'Building' }
    }
    It 'Writes step lines to the verbose stream' {
        $Out = '[1/4] Building CXX object a.obj' | WriteAugmentedOutput -ProgressActivity 'Building' -Verbose 4>&1
        $Out.Message | Should -Be '[1/4] Building CXX object a.obj'
    }
    It 'Passes step lines through when there is no activity' {
        '[1/4] Building CXX object a.obj' | WriteAugmentedOutput | Should -Be '[1/4] Building CXX object a.obj'
    }
    It 'Emits nothing for no input' {
        @() | WriteAugmentedOutput | Should -BeNullOrEmpty
    }
}

Describe 'PSCMake options' {
    It 'Defaults to formatting on, VS Code' {
        Get-PSCMakeOption DiagnosticFormatting | Should -BeTrue
        Get-PSCMakeOption Ide | Should -Be 'VSCode'
    }
    It 'Sets only the options given' {
        Set-PSCMakeOption -Ide VisualStudio
        try {
            Get-PSCMakeOption Ide | Should -Be 'VisualStudio'
            Get-PSCMakeOption DiagnosticFormatting | Should -BeTrue
        } finally {
            Set-PSCMakeOption -Ide VSCode
        }
    }
}
