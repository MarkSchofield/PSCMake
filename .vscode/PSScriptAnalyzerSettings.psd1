@{
    Rules = @{
        PSReviewUnusedParameter = @{
            CommandsToTraverse = @(
                'SearchAncestors'
                'Using-Location'
            )
        }
    }
    IncludeRules = @('*')
    ExcludeRules = @('PSUseApprovedVerbs')
}

