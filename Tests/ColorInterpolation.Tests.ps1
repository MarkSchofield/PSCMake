#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/Common.ps1
}

Describe 'ColorInterpolation' {
    It 'Should return the "From" color when "T" is 0.0' {
        ColorInterpolation ([System.Drawing.Color]::Black) ([System.Drawing.Color]::White) 0.0 |
            ForEach-Object { '{0:x}' -f $_.ToArgb() } |
            Should -Be 'ff000000'
    }
    It 'Should return the "To" color when "T" is 1.0' {
        ColorInterpolation ([System.Drawing.Color]::Black) ([System.Drawing.Color]::White) 1.0 |
            ForEach-Object { '{0:x}' -f $_.ToArgb() } |
            Should -Be 'ffffffff'
    }
    It 'Should return the mid-point color when "T" is 0.5' {
        ColorInterpolation ([System.Drawing.Color]::Black) ([System.Drawing.Color]::White) 0.5 |
            ForEach-Object { '{0:x}' -f $_.ToArgb() } |
            Should -Be 'ff808080'
    }
}
