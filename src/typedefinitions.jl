struct DesignMatrix
    "Array of formulas"
    formulas::Any
    "A concatenated designmatric. In case of Mixed Models an array, where the first one is a FeMat, later ones ReMats. "
    Xs::Any
    "Event table with all events"
    events::Any
end

function DesignMatrix()
    return DesignMatrix([], [], [])
end


abstract type UnfoldModel end

#function UnfoldModel()
# todo make generator function with empty DesignMatrix
mutable struct UnfoldLinearModel <: UnfoldModel
    design::Dict
    designmatrix::DesignMatrix
    modelfit::Any
end

UnfoldLinearModel(d::Dict) = UnfoldLinearModel(d, Unfold.DesignMatrix(), [])
UnfoldLinearModel(d::Dict, X::DesignMatrix) = UnfoldLinearModel(d, X, [])

mutable struct UnfoldLinearMixedModel <: UnfoldModel
    design::Dict
    designmatrix::DesignMatrix
    modelfit::Any#::Array{UnfoldMixedModelFitCollection} # optional info on the modelfit
end
UnfoldLinearMixedModel(d::Dict) = UnfoldLinearMixedModel(d, Unfold.DesignMatrix(), [])
UnfoldLinearMixedModel(d::Dict, X::DesignMatrix) = UnfoldLinearMixedModel(d, X, [])


mutable struct UnfoldLinearModelContinuousTime <: UnfoldModel
    design::Dict
    designmatrix::DesignMatrix
    modelfit::Any
end

UnfoldLinearModelContinuousTime(d::Dict) =
    UnfoldLinearModelContinuousTime(d, Unfold.DesignMatrix(), [])
UnfoldLinearModelContinuousTime(d::Dict, X::DesignMatrix) =
    UnfoldLinearModelContinuousTime(d, X, [])

mutable struct UnfoldLinearMixedModelContinuousTime <: UnfoldModel
    design::Dict
    designmatrix::DesignMatrix
    modelfit::Any#::UnfoldMixedModelFitCollection
end

UnfoldLinearMixedModelContinuousTime(d::Dict) =
    UnfoldLinearMixedModelContinuousTime(d, Unfold.DesignMatrix(), [])
UnfoldLinearMixedModelContinuousTime(d::Dict, X::DesignMatrix) =
    UnfoldLinearMixedModelContinuousTime(d, X, [])


abstract type ModelFit end

struct LinearModelFit <: ModelFit
    estimate::Any
    info::Any
    standarderror::Any
end

LinearModelFit(estimate) = LinearModelFit(estimate, [], [])
LinearModelFit(estimate, info) = LinearModelFit(estimate, info, [])

function Base.show(io::IO, obj::UnfoldModel)
    println(io, "Unfold-Type: $(typeof(obj)) \n")
    println(io, "formula: $(obj.design)")
    println(
        io,
        "Useful functions:\n 
    design(uf) \t\t(returns Dict of event => (formula,times/basis))  \n
    designmatrix(uf) \t(returns DesignMatrix with events) \n
    modelfit(uf) \t\t(returns modelfit object) \n
    coeftable(uf) \t\t(returns tidy result dataframe) \n",
    )
end


abstract type AbstractSplineTerm <:AbstractTerm end
