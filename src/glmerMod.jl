import MixedModels: GeneralizedLinearMixedModel,
                    setθ!,
                    updateL!
import Distributions: Distribution,
                      Bernoulli,
                      Binomial,
                      Gamma,
                      Gaussian,
                      InverseGaussian,
                      Poisson

import GLM: Link,
            CauchitLink,
            CloglogLink,
            LogitLink,
            IdentityLink,
            InverseLink,
            LogLink,
            ProbitLink,
            SqrtLink

import RCall: rcopy,
              RClass,
              rcopytype,
              reval,
              S4Sxp,
              sexp,
              protect,
              unprotect,
              sexpclass,
              @rput,
              @rget
# if RCall is available, then so is DataFrames
import DataFrames: DataFrame, categorical!
import CategoricalArrays: CategoricalArray
import Tables: ColumnTable

# # from R
function rcopy(::Type{GeneralizedLinearMixedModel}, s::Ptr{S4Sxp})
    data = nothing;
    # try
    #     data = rcopy(s[:frame]);
    # catch err
    #     if !isa(err, DimensionMismatch) # matrix columns -- cbind!
    #         throw(err)
    #     end
    # go back up to the original data frame
    # this will only work if that data frame is still available in the
    # current environment. There may be a better way to unwind this
    # but that will involve more R black magic
    data = rcopy(R"eval($(s[:call][:data]))");
    # end
    wts = []
    try
        wts = rcopy(s[:call][:weights])
        wts = data[!, wts]
    catch err
        if !isa(err, BoundsError)
            throw(err)
        end
        # no weights defined, we continue on our way
        try
            wts = rcopy(s[:resp][:n])
        catch err
            if !isa(err, BoundsError)
                throw(err)
            end
            # no weights here either, we continue on our way
        end
    end
    # the function terms are constructed but reference non existent vars
    # need to somehow recontr
    f = convert_r_to_julia(s[:call][:formula])
    family = rcopy(R"$(s[:resp])$family$family")
    if family in ("quasi", "quasibinomial", "quasipoisson")
        throw(ArgumentError("quasi families are not supported"))
    elseif family in ("gaussian", "Gamma", "inverse.gaussian")
        throw(ArgumentError("GLMMs with dispersion parameters are known to give incorrect results in MixedModels.jl (see PR#291), aborting."))
    elseif family in ("poisson", "binomial")
        family = titlecase(family)
    else
        throw(ArgumentError("Unknown and hence unsupported family: $family"))
    end

    family = eval(Symbol(family))

    link = rcopy(R"$(s[:resp])$family$link")
    link in ["logit", "probit", "cauchit",
             "log", "identity", "inverse", "sqrt",
             "cloglog"] || throw(ArgumentError("Link $urlink not supported"))
    link = titlecase(link) * "Link"
    link = eval(Symbol(link))

    nAGQ = rcopy(s[:devcomp][:dims][:nAGQ])
    fast = nAGQ == 0 ? true : false
    if nAGQ == 0
        nAGQ = 1
    end
    θ = rcopy(s[:theta])

    m = GeneralizedLinearMixedModel(f,data, family())#, link(), wts=wts)
    return m
    m.optsum.feval = rcopy(s[:optinfo][:feval])
    try
        m.optsum.final = rcopy(s[:optinfo][:val])
    catch err
        if isa(err, MethodError)
            # this happens if θ has length one, i.e. a single scalar RE
            m.optsum.final = [rcopy(s[:optinfo][:val])]
            θ = [θ]
        else
            throw(err)
        end
    end
    m.optsum.optimizer = Symbol("$(rcopy(s[:optinfo][:optimizer])) (lme4)")
    m.optsum.returnvalue = Bool(rcopy(s[:optinfo][:conv][:opt])) ? :FAILURE : :SUCCESS
    m.optsum.fmin = rcopy(s[:devcomp][:cmp][:dev])
    m.optsum.nAGQ = nAGQ
    setpar! = fast ? setθ! : setβθ!
    updateL!(setpar!(m, θ))
end

rcopytype(::Type{RClass{:glmerMod}}, s::Ptr{S4Sxp}) = GeneralizedLinearMixedModel

# from Julia
function sexp(::Type{RClass{:glmerMod}}, x::Tuple{GeneralizedLinearMixedModel{T}, DataFrame}) where T
    m, tbl = x
    m.optsum.feval > 0 || throw(ArgumentError("Model must be fitted"))

    distribution =  Distribution(m.resp)
    family = urfamily = replace(string(distribution), Regex("{.*}") => "")
    # ["Bernoulli","Binomial","Gamma", "Poisson", "InverseGaussian"]
    # R families: binomial, gaussian, Gamma, inverse.gaussian, poisson
    #             quasi, quasibinomial, quasipoisson
    # should we @warn for the way GLMM deviance is defined in lme4?
    # we construct this piece-by-piece because this keeps the warnings
    # and everything in sync
    supported = ("Bernoulli", "Binomial", "Poisson")
    if family in ("Bernoulli", "Binomial")
        family = "binomial"
    elseif family == "Poisson"
        family = "poisson"
    elseif family in ("Gamma","Gaussian","InverseGaussian")
        throw(ArgumentError("GLMMs with dispersion parameters are known to give incorrect results in MixedModels.jl (see PR#291), aborting."))
    else
        throw(ArgumentError("Family $family is not supported"))
    end

    urlink = string(Link(m.resp))
    link = lowercase(replace(urlink, "Link()" => ""))

    link in ["logit", "probit", "cauchit",
             "log", "identity", "inverse", "sqrt",
             "cloglog"] || throw(ArgumentError("Link $urlink not supported"))

    if length(m.optsum.initial) - length(m.β) < 0
        nAGQ = 0
    else
        nAGQ = m.optsum.nAGQ
    end

    # if !isempty(m.sqrtwts)
    #     @error "weights are not currently supported"
    # end


    # should we assume the user is smart enough?
    reval("library(lme4)")

    jellyme4_data = tbl
    if urfamily == "Bernoulli"
        lhs = m.formula.lhs
        # should we check for PooledArray? brings in another dependency...
        if !(jellyme4_data[!,lhs.sym] isa CategoricalArray)
            @warn "Response was not categorical, converting in place"
            categorical!(jellyme4_data, [lhs.sym])
        end
    end
    formula = convert_julia_to_r(m.formula)

    jellyme4_theta = m.θ
    jellyme4_beta = m.β
    jellyme4_weights = m.wt
    length(jellyme4_weights) > 0 || (jellyme4_weights = nothing)
    fval = m.optsum.fmin
    feval = m.optsum.feval
    conv = m.optsum.returnvalue == :SUCCESS ? 0 : 1
    optimizer = String(m.optsum.optimizer)
    message = "fit with MixedModels.jl"
    rsteps = 1;

    betastart = nAGQ > 0 ? "fixef=jellyme4_beta, " : ""

    @rput jellyme4_data
    @rput jellyme4_theta
    @rput jellyme4_beta
    @rput jellyme4_weights

    set_r_contrasts!("jellyme4_data", m.formula)

    r = """
        jellyme4_mod <- glmer(formula = $(formula),
                               data=jellyme4_data,
                               family=$family(link="$link"),
                               nAGQ=$(nAGQ),
                               weights=jellyme4_weights,
                               control=glmerControl(optimizer="nloptwrap",
                                                    optCtrl=list(maxeval=$(rsteps)),
                                        calc.derivs=FALSE),
                                start=list($(betastart)theta=jellyme4_theta))
         jellyme4_mod@optinfo\$feval <- $(feval)
         jellyme4_mod@optinfo\$message <- "$(message)"
         jellyme4_mod@optinfo\$optimizer <- "$(optimizer)"
         jellyme4_mod
    """
    @debug r
    @warn """Some accuracy is lost in translation for GLMMs. This is fine with plotting, but proceed with caution for inferences.
             You can try letting the model "reconverge" in lme4 with
                 update(model, control=glmerControl(optimizer="nloptwrap", calc.derivs=FALSE))."""
    @info "lme4 handles deviance for GLMMs differently than MixedModels.jl"
    @info "for the correct comparison, examine -2*logLik(RModel) and deviance(JuliaModel)"
    r = reval(r)
    r = protect(sexp(r))
    unprotect(1)
    r
end

sexpclass(x::Tuple{GeneralizedLinearMixedModel{T}, DataFrame}) where T = RClass{:glmerMod}

# generalize to ColumnTable, which is what MixedModels actually requires
function sexp(ss::Type{RClass{:glmerMod}}, x::Tuple{GeneralizedLinearMixedModel{T}, ColumnTable}) where T
    m, t  = x
    sexp(ss, Tuple([m, DataFrame(t)]))
end

sexpclass(x::Tuple{GeneralizedLinearMixedModel{T}, ColumnTable}) where T = RClass{:glmerMod}
