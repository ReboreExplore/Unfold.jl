
"""
fit(type::UnfoldModel,f::FormulaTerm,tbl::DataFrame,data::Array{T,3},times)
fit(type::UnfoldModel,f::FormulaTerm,tbl::DataFrame,data::Array{T,2},basisfunction::BasisFunction)
fit(type::UnfoldModel,d::Dict,tbl::DataFrame,data::Array)

Generates Designmatrix & fits model, either mass-univariate (one model per epoched-timepoint) or time-expanded (modeling linear overlap).


# Examples
Mass Univariate Linear
```julia-repl
julia> data,evts = loadtestdata("testCase1")
julia> data_r = reshape(data,(1,:))
julia> data_e,times = Unfold.epoch(data=data_r,tbl=evts,τ=(-1.,1.9),sfreq=10) # cut the data into epochs. data_e is now ch x times x epoch

julia> f  = @formula 0~1+continuousA+continuousB # 1
julia> model = fit(UnfoldModel,f,evts,data_e,times)
```
Timexpanded Univariate Linear
```julia-repl
julia> basisfunction = firbasis(τ=(-1,1),sfreq=10,name="A")
julia> model = fit(UnfoldModel,Dict(Any=>(f,basisfunction),evts,data_r)
```

"""
function StatsModels.fit(
    UnfoldModelType::Type{T},
    f::FormulaTerm,
    tbl::DataFrame,
    data::AbstractArray,
    basisOrTimes::Union{BasisFunction,AbstractArray};
    kwargs...,
) where {T<:Union{<:UnfoldModel}}
    # old input format, sometimes convenient.Convert to dict-based one
    fit(UnfoldModelType, Dict(Any => (f, basisOrTimes)), tbl, data; kwargs...)
end


function StatsModels.fit(
    UnfoldModelType::Type{UnfoldModel},
    design::Dict,
    tbl::DataFrame,
    data::AbstractArray;
    kwargs...,
    )
    detectedType = designToModeltype(design)

    fit(detectedType,design,tbl,data;kwargs...)
end


function StatsModels.fit(
    UnfoldModelType::Type{<:UnfoldModel},
    design::Dict,
    tbl::DataFrame,
    data::AbstractArray;
    kwargs...,
)
fit(UnfoldModelType(design),design,tbl,data;kwargs...)
end


function StatsModels.fit(
    uf::UnfoldModel,#Union{UnfoldLinearMixedModel,UnfoldLinearModel,UnfoldLinearMixedModelContinuousTime,UnfoldLinearModelContinuousTime},
    design::Dict,
    tbl::DataFrame,
    data::AbstractArray;
    kwargs...,
    )
    
    designmatrix!(uf, tbl; kwargs...)
    fit!(uf, data; kwargs...)

    return uf
end

function StatsModels.fit(
    UnfoldModelType::Type{T},
    X::DesignMatrix,
    data::AbstractArray;
    kwargs...,
) where {T<:Union{<:UnfoldModel}}
    if UnfoldModelType == UnfoldModel
        error(
            "Can't infer model automatically, specify with e.g. fit(UnfoldLinearModel...) instead of fit(UnfoldModel...)",
        )
    end
    uf = UnfoldModelType(Dict(), X)

    fit!(uf, data; kwargs...)

    return uf
end

isMixedModelFormula(f::ConstantTerm) = false
isMixedModelFormula(f::FormulaTerm) = isMixedModelFormula(f.rhs)

function isMixedModelFormula(f::Tuple)
    ix = [isa(t, FunctionTerm) for t in f]
    return any([isa(t.forig, typeof(|))|isa(t.forig,typeof(MixedModels.zerocorr)) for t in f[ix]])
end
function designToModeltype(design)
    # autoDetect
    tmp = collect(values(design))[1]
    f = tmp[1] # formula
    t = tmp[2] # Vector or BasisFunction

    isMixedModel = isMixedModelFormula(f)

    if typeof(t) <: BasisFunction
        if isMixedModel
            UnfoldModelType = UnfoldLinearMixedModelContinuousTime
        else
            UnfoldModelType = UnfoldLinearModelContinuousTime
        end
    else
        if isMixedModel
            UnfoldModelType = UnfoldLinearMixedModel
        else
            UnfoldModelType = UnfoldLinearModel
        end
    end
    return UnfoldModelType
end


# helper function for 1 channel data
function StatsModels.fit(
    ufmodel::T,
    design::Dict,
    tbl::DataFrame,
    data::AbstractVector,
    args...;
    kwargs...,
) where {T<:Union{<:UnfoldModel}}
    @debug("data array is size (X,), reshaping to (1,X)")
    data = reshape(data, 1, :)
    return fit(ufmodel, design, tbl, data, args...; kwargs...)
end

# helper to reshape a 
function StatsModels.fit(
    ufmodel::T,
    design::Dict,
    tbl::DataFrame,
    data::AbstractMatrix,
    args...;
    kwargs...)where {T<:Union{UnfoldLinearMixedModel,UnfoldLinearModel}}
    @debug("MassUnivariate data array is size (X,Y), reshaping to (1,X,Y)")
    data = reshape(data, 1, size(data)...)
    return fit(ufmodel, design, tbl, data, args...; kwargs...)
end


"""
fit!(uf::UnfoldModel,data::Union{<:AbstractArray{T,2},<:AbstractArray{T,3}}) where {T<:Union{Missing, <:Number}}

Fit a DesignMatrix against a 2D/3D Array data along its last dimension
Data is typically interpreted as channel x time (with basisfunctions) or channel x time x epoch (for mass univariate)

Returns an UnfoldModel object

# Examples
```julia-repl
```

"""
function StatsModels.fit!(
    uf::Union{UnfoldLinearMixedModel,UnfoldLinearMixedModelContinuousTime},
    data::AbstractArray;
    kwargs...,
)

    #@assert length(first(values(design(uf)))[2])
    if uf isa UnfoldLinearMixedModel
        if ~isempty(Unfold.design(uf))
        @assert length(Unfold.times(Unfold.design(uf))) == size(data,length(size(data))-1) "Times Vector does not match second last dimension of input data - forgot to epoch, or misspecified 'time' vector?"
        end
    end
    # function content partially taken from MixedModels.jl bootstrap.jl
    df = Array{NamedTuple,1}()
    dataDim = length(size(data)) # surely there is a nicer way to get this but I dont know it

    Xs = modelmatrix(uf)
    # If we have3 dimension, we have a massive univariate linear mixed model for each timepoint
    if dataDim == 3
        firstData = data[1, 1, :]
        ntime = size(data, 2)
    else
        # with only 2 dimension, we run a single time-expanded linear mixed model per channel/voxel
        firstData = data[1, :]
        ntime = 1
    end
    nchan = size(data, 1)

    Xs = (equalizeLengths(Xs[1]),Xs[2:end]...)
    _,data = zeropad(Xs[1],data)
    # get a un-fitted mixed model object
    
    Xs = disallowmissing.(Xs)

    mm = LinearMixedModel_wrapper(formula(uf), firstData, Xs)
    # prepare some variables to be used
    βsc, θsc = similar(MixedModels.coef(mm)), similar(mm.θ) # pre allocate
    p, k = length(βsc), length(θsc)
    #β_names = (Symbol.(fixefnames(mm))..., )

    β_names = (Symbol.(vcat(fixefnames(mm)...))...,)
    β_names = (unique(β_names)...,)

    @assert(
        length(β_names) == length(βsc),
        "Beta-Names & coefficient length do not match. Did you provide two identical basis functions?"
    )

    @debug println("beta_names $β_names")
    @debug println("uniquelength: $(length(unique(β_names))) / $(length(β_names))")
    # for each channel
    prog = Progress(nchan * ntime, 0.1)
    #@showprogress .1 
    for ch in range(1, stop = nchan)
        # for each time
        for t in range(1, stop = ntime)

            #@debug "ch:$ch/$nchan, t:$t/$ntime"
            @debug "data-size: $(size(data))"
            #@debug println("mixedModel: $(mm.feterms)")
            if ndims(data) == 3
                MixedModels.refit!(mm, data[ch, t, :])
            else
                MixedModels.refit!(mm, data[ch, :])
            end
            #@debug println(MixedModels.fixef!(βsc,mm))

            β = NamedTuple{β_names}(MixedModels.fixef!(βsc, mm))

            out = (
                objective = mm.objective,
                σ = mm.σ,
                β = NamedTuple{β_names}(MixedModels.fixef!(βsc, mm)),
                se = SVector{p,Float64}(MixedModels.stderror!(βsc, mm)), #SVector not necessary afaik, took over from MixedModels.jl
                θ = SVector{k,Float64}(MixedModels.getθ!(θsc, mm)),
                channel = ch,
                timeIX = ifelse(dataDim == 2, NaN, t),
            )
            push!(df, out)
            ProgressMeter.next!(prog; showvalues = [(:channel, ch), (:time, t)])
        end
    end

    uf.modelfit = UnfoldMixedModelFitCollection(
        df,
        deepcopy(mm.λ),
        getfield.(mm.reterms, :inds),
        copy(mm.optsum.lowerbd),
        NamedTuple{Symbol.(fnames(mm))}(map(t -> (t.cnames...,), mm.reterms)),
    )


    return uf.modelfit
end

function StatsModels.coef(
    uf::Union{UnfoldLinearMixedModel,UnfoldLinearMixedModelContinuousTime},
)
    beta = [x.β for x in MixedModels.tidyβ(modelfit(uf))]
    return reshape_lmm(uf, beta)
end

function MixedModels.ranef(
    uf::Union{UnfoldLinearMixedModel,UnfoldLinearMixedModelContinuousTime},
)
    sigma = [x.σ for x in MixedModels.tidyσs(modelfit(uf))]
    return reshape_lmm(uf, sigma)
end

function reshape_lmm(uf::UnfoldLinearMixedModel, est)
    ntime = length(collect(values(design(uf)))[1][2])
    nchan = modelfit(uf).fits[end].channel
    return permutedims(reshape(est, :, ntime, nchan), [3 2 1])
end
function reshape_lmm(uf::UnfoldLinearMixedModelContinuousTime, est)
    nchan = modelfit(uf).fits[end].channel
    return reshape(est, :, nchan)'

end





function StatsModels.fit!(
    uf::Union{UnfoldLinearModelContinuousTime,UnfoldLinearModel},
    data;
    solver = (x, y) -> solver_default(x, y),
    kwargs...,
)

    @assert ~isempty(designmatrix(uf))
    @assert typeof(first(values(design(uf)))[1]) <: FormulaTerm "InputError in design(uf) - :key=>(FORMULA,basis/times), formula not found. Maybe formula wasn't at the first place?"
    @assert (typeof(first(values(design(uf)))[2]) <: AbstractVector) ⊻ (typeof(uf) <: UnfoldLinearModelContinuousTime) "InputError: Either a basis function was declared, but a UnfoldLinearModel was built, or a times-vector (and no basis function) was given, but a UnfoldLinearModelContinuousTime was asked for."
    if isa(uf,UnfoldLinearModel)
        @assert length(first(values(design(uf)))[2]) == size(data,length(size(data))-1) "Times Vector does not match second last dimension of input data - forgot to epoch?"
    end
   
    X = modelmatrix(uf)

    @debug "UnfoldLinearModel(ContinuousTime), datasize: $(size(data))"
    
    if isa(uf,UnfoldLinearModel)
        d = designmatrix(uf)

        if isa(X,Vector)
        # mass univariate with multiple events fitted at the same time
        
        coefs = []
        for m = 1:length(X)
            # the main issue is, that the designmatrices are subsets of the event table - we have 
            # to do the same for the data, but data and designmatrix dont know much about each other.
            # Thus we use parentindices() to get the original indices of the @view events[...] from desigmatrix.jl
            push!(coefs,solver(X[m], @view data[:,:,parentindices(d.events[m])[1]]))
        end
        @debug @show [size(c.estimate) for c in coefs]
        uf.modelfit = LinearModelFit(
            cat([c.estimate for c in coefs]...,dims=3),
            [c.info for c in coefs],
            cat([c.standarderror for c in coefs]...,dims=3)
        )
        return # we are done here
   
        elseif isa(d.events,SubDataFrame)
            # in case the user specified an event to subset (and not any) we have to use the view from now on
            data = @view data[:,:,parentindices(d.events)[1]]
        end
    end


        # mass univariate, data = ch x times x epochs
        X, data = zeropad(X, data)

        uf.modelfit = solver(X, data)
        return

end


LinearMixedModel_wrapper(form,data::Array{<:Union{TData},1},Xs;wts = []) where {TData<:Union{Missing,Number}}= @error("currently no support for missing values in MixedModels.jl")

"""
$(SIGNATURES)

Wrapper to generate a LinearMixedModel. Code taken from MixedModels.jl and slightly adapted.

"""
function LinearMixedModel_wrapper(
    form,
    data::Array{<:Union{TData},1},
    Xs;
    wts = [],
) where {TData<:Number}
    #    function LinearMixedModel_wrapper(form,data::Array{<:Union{Missing,TData},1},Xs;wts = []) where {TData<:Number}
    Xs = (equalizeLengths(Xs[1]),Xs[2:end]...)
    # XXX Push this to utilities zeropad
    # Make sure X & y are the same size
    m = size(Xs[1])[1]


    if m != size(data)[1]
        fe,data = zeropad(Xs[1],data)
        
        Xs = changeMatSize!(size(data)[1], fe, Xs[2:end])
    end

    y = (reshape(float(data), (:, 1)))
    
    MixedModels.LinearMixedModel(y, Xs, form, wts)
end

function MixedModels.LinearMixedModel(y, Xs, form::Array, wts)


    form_combined = form[1]
    for f in form[2:end]

        form_combined =
            form_combined.lhs ~
                MatrixTerm(form_combined.rhs[1] + f.rhs[1]) +
                form_combined.rhs[2:end] +
                f.rhs[2:end]
    end
    MixedModels.LinearMixedModel(y, Xs, form_combined, wts)
end
