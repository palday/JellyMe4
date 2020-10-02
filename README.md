# JellyMe4

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://palday.github.io/JellyMe4.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://palday.github.io/JellyMe4.jl/dev)
[![Build Status](https://travis-ci.com/palday/JellyMe4.jl.svg?branch=master)](https://travis-ci.com/palday/JellyMe4.jl)
[![Codecov](https://codecov.io/gh/palday/JellyMe4.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/palday/JellyMe4.jl)

<!-- [![Build Status](https://ci.appveyor.com/api/projects/status/github/palday/JellyMe4.jl?svg=true)](https://ci.appveyor.com/project/palday/JellyMe4-jl) -->

## Purpose
One of the difficulties in transitioning to a new programming language is not just learning how to do things in the new language, but the difference in the package ecosystem. `RCall` helps with both aspects when moving from R to Julia, at least when it comes to basic data manipulation. `JellyMe4` takes advantage of `RCall`'s extensibility to provide a way to transfer mixed-effects models fit between R's `lme4` and Julia's `MixedEffectsModels`. This means that it is now possible to fit a model in Julia, but then take advantage of existing R packages for examing the model such as `car` and `effects`.

## Installation

`JellyMe4` is now registered in the Julia package registry and can be installed by
```julia
julia> using Pkg
julia> Pkg.add("JellyMe4")

```
or, in the pkg REPL,
```julia
(@v1.4) pkg> add JellyMe4
```

To get the latest pre-release features, you can install the development version:
```julia
(@v1.4) pkg> add JellyMe4#master
```

Generally speaking, the development version should work, but especially until version 1.0, there is no guarantee that there won't be breaking changes compared to the latest release.

## Basic Usage

### Fitting a model in R and moving it to Julia:

```julia
julia> using MixedModels, RCall, JellyMe4
julia> R"library(lme4)"
┌ Warning: RCall.jl: Loading required package: Matrix
└ @ RCall ~/.julia/packages/RCall/g7dhB/src/io.jl:113
RObject{StrSxp}
[1] "lme4"      "Matrix"    "stats"     "graphics"  "grDevices" "utils"    
[7] "datasets"  "methods"   "base"     

julia> R"summary(m <- lmer(Reaction ~ 1 + Days + (1+Days|Subject),sleepstudy,REML=FALSE))"
RObject{VecSxp}
Linear mixed model fit by maximum likelihood  ['lmerMod']
Formula: Reaction ~ 1 + Days + (1 + Days | Subject)
   Data: sleepstudy

     AIC      BIC   logLik deviance df.resid
  1763.9   1783.1   -876.0   1751.9      174

Scaled residuals:
    Min      1Q  Median      3Q     Max
-3.9416 -0.4656  0.0289  0.4636  5.1793

Random effects:
 Groups   Name        Variance Std.Dev. Corr
 Subject  (Intercept) 565.48   23.780       
          Days         32.68    5.717   0.08
 Residual             654.95   25.592       
Number of obs: 180, groups:  Subject, 18

Fixed effects:
            Estimate Std. Error t value
(Intercept)  251.405      6.632  37.907
Days          10.467      1.502   6.968

Correlation of Fixed Effects:
     (Intr)
Days -0.138


julia> @rget m
Linear mixed model fit by maximum likelihood
 Reaction ~ 1 + Days + (1 + Days | Subject)
   logLik   -2 logLik     AIC        BIC    
 -875.96967 1751.93934 1763.93934 1783.09709

Variance components:
            Column    Variance   Std.Dev.    Corr.
Subject  (Intercept)  565.476967 23.7797596
         Days          32.681785  5.7167985  0.08
Residual              654.945706 25.5919070
 Number of obs: 180; levels of grouping factors: 18

  Fixed-effects parameters:
───────────────────────────────────────────────────
             Estimate  Std.Error   z value  P(>|z|)
───────────────────────────────────────────────────
(Intercept)  251.405     6.63212  37.9072    <1e-99
Days          10.4673    1.50223   6.96783   <1e-11
───────────────────────────────────────────────────
julia> typeof(m)
LinearMixedModel{Float64}
```

### Fitting a model in Julia and moving it to R
```julia
julia> using MixedModels, RCall, JellyMe4
julia> machines = rcopy(R"nlme::Machines")
54×3 DataFrames.DataFrame
│ Row │ Worker       │ Machine      │ score   │
│     │ Categorical… │ Categorical… │ Float64 │
├─────┼──────────────┼──────────────┼─────────┤
│ 1   │ 1            │ A            │ 52.0    │
│ 2   │ 1            │ A            │ 52.8    │
│ 3   │ 1            │ A            │ 53.1    │
│ 4   │ 2            │ A            │ 51.8    │
│ 5   │ 2            │ A            │ 52.8    │
│ 6   │ 2            │ A            │ 53.1    │
⋮
│ 48  │ 4            │ C            │ 64.0    │
│ 49  │ 5            │ C            │ 72.1    │
│ 50  │ 5            │ C            │ 72.0    │
│ 51  │ 5            │ C            │ 71.1    │
│ 52  │ 6            │ C            │ 62.0    │
│ 53  │ 6            │ C            │ 61.4    │
│ 54  │ 6            │ C            │ 60.5    │

julia> m = fit(MixedModel, @formula(score ~ 1 + Machine + (1 + Machine|Worker)), machines)
Linear mixed model fit by maximum likelihood
 score ~ 1 + Machine + (1 + Machine | Worker)
   logLik    -2 logLik      AIC         BIC     
 -108.208914  216.417828  236.417828  256.307668

Variance components:
            Column     Variance   Std.Dev.   Corr.
Worker   (Intercept)  13.81760447 3.7172039
         Machine: B   28.68496515 5.3558347  0.49
         Machine: C   11.24097825 3.3527568 -0.36  0.30
Residual               0.92463436 0.9615791
 Number of obs: 54; levels of grouping factors: 6

  Fixed-effects parameters:
───────────────────────────────────────────────────
             Estimate  Std.Error   z value  P(>|z|)
───────────────────────────────────────────────────
(Intercept)  52.3556     1.53437  34.1218    <1e-99
Machine: B    7.96667    2.20988   3.60502   0.0003
Machine: C   13.9167     1.40579   9.89956   <1e-22
───────────────────────────────────────────────────
julia> # LinearMixedModel doesn't keep of the original dataframe,
julia> # so we need to package it up
julia> m_machines = (m, machines);
julia> @rput m_machines;
julia> R"summary(m_machines)"
RObject{VecSxp}
Linear mixed model fit by maximum likelihood  ['lmerMod']

     AIC      BIC   logLik deviance df.resid
   236.4    256.3   -108.2    216.4       44

Scaled residuals:
     Min       1Q   Median       3Q      Max
-2.40773 -0.51890  0.03227  0.45598  2.54091

Random effects:
 Groups   Name        Variance Std.Dev. Corr       
 Worker   (Intercept) 13.8176  3.7172              
          MachineB    28.6850  5.3558    0.49      
          MachineC    11.2410  3.3528   -0.36  0.30
 Residual              0.9246  0.9616              
Number of obs: 54, groups:  Worker, 6

Fixed effects:
            Estimate Std. Error t value
(Intercept)   52.356      1.534  34.122
MachineB       7.967      2.210   3.605
MachineC      13.917      1.406   9.900

Correlation of Fixed Effects:
         (Intr) MachnB
MachineB  0.463       
MachineC -0.374  0.301
```

## Limitations and warnings

This is alpha software. It has some functionality that should work well for common use cases and even a testsuite, but this testsuite depends on two different software environments (R and Julia) and can afoul of all sorts of nasty version interactions. The testuite only tests against a single version of R and the current version of lme4. In other words, even for the parts that do work for me, they may not work for you.

Parts of the API aren't as nice as I would like them to be (especially in the Julia to R direction) and may change if I figure out something nicer.

Only a subset of all the options available in `MixedModels` and `lme4` are supported. Unsupported things should break in an obvious way, but here's a list of things that are more commonly used but may break non obviously:
- ~~**custom contrast coding**. If you really need this and you know what you're doing, then you can set up your own numeric variables representing appropriate contrasts, as numeric variables survive the transition without difficulty.~~ This should work if you're not doing anything weird with your interaction terms.
- **advanced models in either language** ~(e.g., `zerocorr!`, `fulldummy` in Julia or `||` in R, which are not completely synonymous anyway).~ `fulldummy` in Julia and `||` in R should work. `zerocorr` will work for continuous variables and factors with two levels, but won't work with factors with more than two levels. There's not really a trivial way to deal with this at the moment, sorry. Posthoc `zerocorr!` is not detected. Use `zerocorr` in your formula instead.
- **fancy transformations within model formulae**, especially those that have different names (e.g. `scale()` in R). If in doubt, pre-transform your data in the dataframe before fitting. A few transformations are supported (e.g. `log`, `exp`) and you should receive an error for unsupported transformations, but it's always a good idea to compare the estimates of the original and copied models.
- **missing data** is handled differently in R and Julia, both in its representation and when it's eliminated. If in doubt, remove missing data before fitting models for consistency.
- **interactions specified in R with `^`**. This part of the parsing is handled by RCall and winds up getting translated into simple exponentiation instead of "interactions below a certain order".  Consider using the [`simplify.formula`](https://www.rdocumentation.org/packages/MuMIn/versions/1.9.5/topics/Formula%20manipulation) function from the [`MuMIn` package](https://cran.r-project.org/web/packages/MuMIn/index.html) in R to simplify your formula to primitive operations before calling lme4.
- **other R-specific extensions to Wilkinson-Roger notation**. This includes `%in%` for nesting, (`/` for nesting, with reversed order should work because lme4 and MixedModels both handle that specially), `I()` for literal interpretation of arithmetic, `offset()`.
- **rank deficiency in the fixed effects** is handled differently in R and Julia. If in doubt, [remove extraneous columns/predictors](https://juliastats.org/MixedModels.jl/dev/rankdeficiency/#Rank-deficiency-in-mixed-effects-models) before fitting models for consistency.  
- **GLMMs with dispersion parameters**. This should error when unsupported model types are encountered. This is intentionally not supported at the moment because there are [known problems with these models in MixedModels.jl](JuliaStats/MixedModels#291).
- **getting binomial GLMMs from R with any of the alternative specifications**, e.g. `cbind(successes, failures)` or `successes/total`. You will receive a gentle reminder in the form of an error. Note that even once this is supported, you're subject to the constraints above. 
- **getting GLMMs with `quasi` families from R**. The corresponding distributions aren't in Distributions.jl and are only "quasi" in the GLM/GLMM framework.
- **a number of scratch variables in R prefixed by `jellyme4_` are created.** We need scratch variables when moving things to R, so we use  identifiers beginning with `jellyme4_`.

Finally, to work its magic, this package hooks into `MixedModels` and `lme4` internals. `lme4`'s internals are quite stable now and this is taken advantage of by several other R packages (`ordinal`, `gamm4`, `robustlmm`). `MixedModels` are also fairly stable for the core things, but not everything. I am a contributor to `MixedModels`, so I generally know when something is going to change, but things may still break with changing `MixedModels` versions, especially for major version changes.

Models fit with the R package [`afex`](https://cran.r-project.org/web/packages/afex/) should also largely be compatible, as `afex` works by providing a more convenient interface to `lme4`. Note however that if any of `afex`'s behind the scenes rewrite-rules invoke features not yet supported, then the resulting models will not work with JellyMe4. Please check your model summary on both sides to make sure they line up!

## Where does the name come from?

A really bad pun.

If you take `lme4` and add a J for Julia and try to say the resulting string quickly, it sounds a bit like the package name.

Sorry, not sorry.

## Acknowledgements

The development of this package was supported by the Center for Interdisciplinary Research, Bielefeld (ZiF) Cooperation Group "Statistical models for psychological and linguistic data".
