@{
    # Script module or binary module file associated with this manifest.
    RootModule           = 'PSCMake'

    # Version number of this module.
    ModuleVersion        = '0.1'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID                 = 'a686d9ac-cdd5-4881-bca6-2f4556a6817e'

    # Author of this module
    Author               = 'Mark Schofield'

    # Company or vendor of this module
    CompanyName          = 'Unknown'

    # Copyright statement for this module
    Copyright            = '(c) Mark Schofield. All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'PSCMake provides cmdlets for working with CMakePreset-based CMake builds.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion    = '7.0'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport    = @(
        'Build-CMakeBuild'
        'Configure-CMakeBuild'
        'Write-CMakeBuild'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport      = @(
    )

    # Variables to export from this module
    VariablesToExport    = ''

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport      = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData          = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags                     = @(
                'cmake'
                'CMakePresets.json'
            )

            # A URL to the license for this module.
            LicenseUri               = 'https://raw.githubusercontent.com/MarkSchofield/PSCMake/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri               = 'https://github.com/MarkSchofield/PSCMake'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            # ReleaseNotes = ''

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()

        }
    }
}

