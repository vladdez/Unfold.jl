"""
$(SIGNATURES)
using DataFrames: AbstractAggregate
using DataFrames: AbstractAggregate
using DataFrames: AbstractAggregate
Combine two UnfoldDesignmatrices. This allows combination of multiple events.

This also allows to define events with different lengths.

Not supported for models without timebasis, as it is not needed there (one can simply run multiple models)
# Examples
```julia-repl
julia>  basisfunction1 = firbasis(τ=(0,1),sfreq = 10,name="basis1")
julia>  basisfunction2 = firbasis(τ=(0,0.5),sfreq = 10,name="basis2")
julia>  Xdc1          = designmatrix(UnfoldLinearModelContinuousTime([Any=>(@formula 0~1,basisfunction1)],tbl_1)
julia>  Xdc2          = designmatrix(UnfoldLinearModelContinuousTime([Any=>(@formula 0~1,basisfunction2)],tbl_2)
julia>  Xdc = Xdc1+Xdc2 
```

"""
function combine_designmatrices(X1::T, X2::T) where {T<:AbstractDesignMatrix}

    @error "deprecated, shouldnt reach"

    X1 = deepcopy(X1)
    X2 = deepcopy(X2)
    modelmatrix1 = get_modelmatrix(X1)
    modelmatrix2 = get_modelmatrix(X2)
    @assert !((length(modelmatrix1) > 1) && (length(modelmatrix2) > 1)) "it is currently not possible to combine desigmatrices from two already concatenated designs - please concatenate one after the other"

    Xcomb = append!(modelmatrix1, modelmatrix2)


    if typeof(X1.modelmatrix) <: Tuple
        Xcomb = lmm_combine_modelmatrix!(Xcomb, X1, X2)
    end

    if X1.formulas isa FormulaTerm
        # due to the assertion above, we can assume we have only 2 formulas here
        if X1.formulas.rhs isa Unfold.TimeExpandedTerm
            fcomb = Vector{FormulaTerm{<:InterceptTerm,<:TimeExpandedTerm}}(undef, 2)
        else
            fcomb = Vector{FormulaTerm}(undef, 2) # mass univariate case
        end
        fcomb[1] = X1.formulas
        fcomb[2] = X2.formulas
        return T(fcomb, Xcomb, [events(X1), events(X2)])
    else
        if X1.formulas[1].rhs isa Unfold.TimeExpandedTerm
            # we can ignore length of X2, as it has to be a single formula due to the assertion above
            fcomb = Vector{FormulaTerm{<:InterceptTerm,<:TimeExpandedTerm}}(
                undef,
                length(X1.formulas) + 1,
            )
        else
            fcomb = Vector{FormulaTerm}(undef, length(X1.formulas) + 1) # mass univariate case
        end
        fcomb[1:end-1] = formulas(X1)
        fcomb[end] = formulas(X2)[1]
        @debug typeof(Xcomb)
        return T(fcomb, Xcomb, [events(X1)..., events(X2)])
    end
end


Base.:+(X1::Vector{T}, X2::T) where {T<:AbstractDesignMatrix} = [X1..., X2]
Base.:+(X1::T, X2::T) where {T<:AbstractDesignMatrix} = [X1, X2]
Base.:+(X1::Nothing, X2::AbstractDesignMatrix) = [X2]


# helper to get the fixef of lmm but the normal matrix elsewhere
get_modelmatrix(modelmatrix::Tuple) = modelmatrix[1]
get_modelmatrix(modelmatrix::AbstractMatrix) = modelmatrix

#function get_modelmatrix(modelmatrix::AbstractArray)
# mass univariate case
# mass univariate case with multiple events
#    return modelmatrix
#end

"""
Typically returns the field X.modelmatrix of the designmatrix

Compare to `modelmatrix` which further concatenates the designmatrices (in the UnfoldLinearModelContinuousTime) as needed
"""
get_modelmatrix(X::AbstractDesignMatrix) = get_modelmatrix(X.modelmatrix)
get_modelmatrix(X::Vector{<:AbstractDesignMatrix}) = get_modelmatrix.(X)

"""
$(SIGNATURES)
designmatrix(type, f, tbl; kwargs...)
Return a *DesignMatrix* used to fit the models.
# Arguments
- type::UnfoldModel
- f::FormulaTerm: Formula to be used in this designmatrix
- tbl: Events (usually a data frame) to be modelled
- basisfunction::BasisFunction: basisfunction to be used in modeling (if specified)
- contrasts::Dict: (optional) contrast to be applied to formula
- eventfields::Array: (optional) Array of symbols which are passed to basisfunction event-wise. 
First field of array always defines eventonset in samples. Default is [:latency]

# Examples
```julia-repl
julia>  designmatrix(UnfoldLinearModelContinuousTime,Dict(Any=>(f,basisfunction1),tbl)
```

"""
function designmatrix(
    unfoldmodeltype::Type{<:UnfoldModel},
    f::Union{Tuple,FormulaTerm},
    tbl,
    basisfunction;
    contrasts = Dict{Symbol,Any}(),
    kwargs...,
)
    @debug("generating DesignMatrix")

    # check for missings-columns - currently missings not really supported in StatsModels
    s_tmp = schema(f, tbl, contrasts) # temporary scheme to get necessary terms
    neededCols = [v.sym for v in values(s_tmp.schema)]

    tbl_nomissing = DataFrame(tbl) # tbl might be a SubDataFrame due to a view - but we can't modify a subdataframe, can we?
    try
        disallowmissing!(tbl_nomissing, neededCols) # if this fails, it means we have a missing value in a column we need. We do not support this
    catch e
        if e isa ArgumentError
            error(
                e.msg *
                "\n we tried to get rid of a event-column declared as type Union{Missing,T}. But there seems to be some actual missing values in there. 
    You have to replace them yourself (e.g. replace(tbl.colWithMissingValue,missing=>0)) or impute them otherwise.",
            )
        else
            rethrow()
        end
    end



    @debug "applying schema $unfoldmodeltype"
    form = unfold_apply_schema(unfoldmodeltype, f, schema(f, tbl_nomissing, contrasts))

    form =
        apply_basisfunction(form, basisfunction, get(Dict(kwargs), :eventfields, nothing))

    # Evaluate the designmatrix

    #note that we use tbl again, not tbl_nomissing.
    @debug typeof(form)


    X = modelcols(form.rhs, tbl)
    @debug typeof(X)
    @debug unfoldmodeltype
    designmatrixtype = typeof(designmatrix(unfoldmodeltype())[1])
    @debug typeof(form), typeof(X), typeof(tbl), designmatrixtype
    return designmatrixtype(form, X, tbl)
end

"""
    designmatrix(type, f, tbl; kwargs...)
call without basis function, continue with basisfunction = `nothing`
"""
function designmatrix(type, f, tbl; kwargs...)
    return designmatrix(type, f, tbl, nothing; kwargs...)
end




"""
wrapper to make apply_schema mixed models as extension possible

Note: type is not necessary here, but for LMM it is for multiple dispatch reasons!
"""
unfold_apply_schema(type, f, schema) = apply_schema(f, schema, UnfoldModel)


# specify for abstract interface
designmatrix(uf::UnfoldModel) = uf.designmatrix



"""
    designmatrix(
        uf::UnfoldModel,
        tbl;
        eventcolumn = :event,
        contrasts = Dict{Symbol,Any}(),
        kwargs...,
    
Main function, generates the designmatrix, returns a list of `<:AbstractDesignMatrix`

"""
function designmatrix(
    uf::UnfoldModel,
    tbl;
    eventcolumn = :event,
    contrasts = Dict{Symbol,Any}(),
    kwargs...,
)

    X = nothing
    fDict = design(uf)
    for (eventname, f) in fDict

        @debug "Eventname, X:", eventname, X
        if eventname == Any
            eventTbl = tbl
        else
            if !((eventcolumn ∈ names(tbl)) | (eventcolumn ∈ propertynames(tbl)))
                error(
                    "Couldnt find columnName: " *
                    string(eventcolumn) *
                    " in event-table.  Maybe need to specify eventcolumn=:correctColumnName (default is ':event') \n names(tbl) = " *
                    join(names(tbl), ","),
                )
            end
            eventTbl = @view tbl[tbl[:, eventcolumn].==eventname, :] # we need a view so we can remap later if needed
        end
        if isempty(eventTbl)
            error(
                "eventTable empty after subsetting. Couldnt find event '" *
                string(eventname) *
                "'{" *
                string(typeof(eventname)) *
                "}, in field tbl[:,:" *
                string(eventcolumn) *
                "].? - maybe you need to specify it as a string instead of a symbol?",
            )
        end

        fIx = collect(typeof.(f) .<: FormulaTerm)
        bIx = collect(typeof.(f) .<: BasisFunction)



        if any(bIx)
            # timeContinuos way
            # TODO there should be a julian way to do this distinction

            X =
                X + designmatrix(
                    typeof(uf),
                    f[fIx],
                    eventTbl,
                    collect(f[bIx])[1];
                    contrasts = contrasts,
                    kwargs...,
                )
        else
            # normal way
            @debug f
            X =
                X +
                designmatrix(typeof(uf), f[fIx], eventTbl; contrasts = contrasts, kwargs...)
        end
    end
    return X
end

import Base.isempty
Base.isempty(d::AbstractDesignMatrix) = isempty(get_modelmatrix(d))

"""
$(SIGNATURES)
timeexpand the rhs-term of the formula with the basisfunction

"""
function apply_basisfunction(form, basisfunction::BasisFunction, eventfields)
    @debug("apply_basisfunction")
    return FormulaTerm(form.lhs, TimeExpandedTerm(form.rhs, basisfunction, eventfields))
end

function apply_basisfunction(form, basisfunction::Nothing, eventfields)
    # in case of no basisfunctin, do nothing
    return form
end


function designmatrix!(uf::UnfoldModel{T}, evts; kwargs...) where {T}
    X = designmatrix(uf, evts; kwargs...)
    uf.designmatrix = X
    return uf
end

function StatsModels.modelmatrix(uf::UnfoldLinearModel, basisfunction)
    if basisfunction
        @warn("basisfunction not defined for this kind of model")
    else
        return modelmatrix(uf)
    end
end

# catch all case
equalize_lengths(modelmatrix::AbstractMatrix) = modelmatrix

# UnfoldLinearMixedModelContinuousTime case
equalize_lengths(modelmatrix::Tuple) =
    (equalize_lengths(modelmatrix[1]), modelmatrix[2:end]...)

# UnfoldLinearModel - they have to be equal already
equalize_lengths(modelmatrix::Vector{<:AbstractMatrix}) = modelmatrix

#UnfoldLinearModelContinuousTime
equalize_lengths(modelmatrix::Vector{<:SparseMatrixCSC}) = equalize_lengths(modelmatrix...)
equalize_lengths(modelmatrix1::SparseMatrixCSC, modelmatrix2::SparseMatrixCSC, args...) =
    equalize_lengths(equalize_lengths(modelmatrix1, modelmatrix2), args...)
function equalize_lengths(modelmatrix1::SparseMatrixCSC, modelmatrix2::SparseMatrixCSC)
    sX1 = size(modelmatrix1, 1)
    sX2 = size(modelmatrix2, 1)

    # append 0 to the shorter designmat
    if sX1 < sX2
        modelmatrix1 = SparseMatrixCSC(
            sX2,
            modelmatrix1.n,
            modelmatrix1.colptr,
            modelmatrix1.rowval,
            modelmatrix1.nzval,
        )
    elseif sX2 < sX1
        modelmatrix2 = SparseMatrixCSC(
            sX1,
            modelmatrix2.n,
            modelmatrix2.colptr,
            modelmatrix2.rowval,
            modelmatrix2.nzval,
        )
    end
    return hcat(modelmatrix1, modelmatrix2)
end
function StatsModels.modelmatrix(uf::UnfoldLinearModelContinuousTime, basisfunction = true)
    if basisfunction
        return modelmatrix(designmatrix(uf))
        #return hcat(modelmatrix(designmatrix(uf))...)
    else
        # replace basisfunction with non-timeexpanded one
        f = formulas(uf)

        # probably a more julian way to do this...
        if isa(f, AbstractArray)
            return modelcols_nobasis.(f, events(uf))
        else
            return modelcols_nobasis(f, events(uf))
        end

    end
end

modelcols_nobasis(f::FormulaTerm, tbl::AbstractDataFrame) = modelcols(f.rhs.term, tbl)
StatsModels.modelmatrix(uf::UnfoldModel) = modelmatrix(designmatrix(uf))#modelmatrix(uf.design,uf.designmatrix.events)
StatsModels.modelmatrix(d::AbstractDesignMatrix) = get_modelmatrix(d)
StatsModels.modelmatrix(d::Vector{<:AbstractDesignMatrix}) =
    equalize_lengths(get_modelmatrix.(d))
get_modelmatrix

#StatsModels.modelmatrix(d::Dict, events) = modelcols(formulas(d).rhs, events)

formulas(uf::UnfoldModel) = formulas(designmatrix(uf))
formulas(d::AbstractDesignMatrix) = d.formula
formulas(d::Vector{<:AbstractDesignMatrix}) = formulas.(d)

events(uf::UnfoldModel) = events(designmatrix(uf))
events(d::AbstractDesignMatrix) = d.events
events(d::Vector{<:AbstractDesignMatrix}) = events.(d)

design(uf::UnfoldModel) = uf.design

function formulas(d::Dict) #TODO Specify Dict better
    if length(values(d)) == 1
        return [c[1] for c in collect(values(d))][1]
    else
        return [c[1] for c in collect(values(d))]
    end

end

"""
$(SIGNATURES)
calculates in which rows the individual event-basisfunctions should go in Xdc

timeexpand_rows timeexpand_vals
"""
function timeexpand_rows(onsets, bases, shift, ncolsX)
    # generate rowindices
    rows = copy(rowvals.(bases))

    # this shift is necessary as some basisfunction time-points can be negative. But a matrix is always from 1:τ. Thus we have to shift it backwards in time.
    # The onsets are onsets-1 XXX not sure why.
    for r in eachindex(rows)
        rows[r] .+= floor(onsets[r] - 1) .+ shift
    end


    rows_red = reduce(vcat, rows)
    rows_red = repeat(rows_red, ncolsX)
    return rows_red
end

"""
$(SIGNATURES)
calculates the actual designmatrix for a timeexpandedterm. Multiple dispatch on StatsModels.modelcols
"""
function StatsModels.modelcols(term::TimeExpandedTerm, tbl)
    @debug term.term, first(tbl)
    X = modelcols(term.term, tbl)

    time_expand(X, term, tbl)
end


# helper function to get the ranges from where to where the basisfunction is added
function get_timeexpanded_time_range(onset, basisfunction)
    npos = sum(times(basisfunction) .>= 0)
    nneg = sum(times(basisfunction) .< 0)

    #basis = kernel(basisfunction)(onset)

    fromRowIx = floor(onset) - nneg
    toRowIx = floor(onset) + npos

    range(fromRowIx, stop = toRowIx)
end


function timeexpand_cols_allsamecols(bases, ncolsBasis::Int, ncolsX)
    repeatEach = length(nzrange(bases[1], 1))
    cols_r = UnitRange{Int64}[
        ((1:ncolsBasis) .+ ix * ncolsBasis) for ix in (0:ncolsX-1) for b = 1:length(bases)
    ]

    cols = reduce(vcat, cols_r)

    cols = repeat(cols, inner = repeatEach)
    return cols
end

"""
$(SIGNATURES)


calculates in which rows the individual event-basisfunctions should go in Xdc

see also timeexpand_rows timeexpand_vals
"""
function timeexpand_cols(term, bases, ncolsBasis, ncolsX)
    # we can generate the columns much faster, if all bases output the same number of columns 
    fastpath = time_expand_allBasesSameCols(term.basisfunction, bases, ncolsBasis)

    if fastpath
        return timeexpand_cols_allsamecols(bases, ncolsBasis, ncolsX)
    else
        return timeexpand_cols_generic(bases, ncolsBasis, ncolsX)
    end
end

function timeexpand_cols_generic(bases, ncolsBasis, ncolsX)
    # it could happen, e.g. for bases that are duration modulated, that each event has different amount of columns
    # in that case, we have to go the slow route
    cols = Vector{Int64}[]

    for Xcol = 1:ncolsX
        for b = 1:length(bases)
            coloffset = (Xcol - 1) * ncolsBasis
            for c = 1:ncolsBasis
                push!(cols, repeat([c + coloffset], length(nzrange(bases[b], c))))
            end
        end
    end
    return reduce(vcat, cols)


end

function timeexpand_vals(bases, X, nTotal, ncolsX)
    # generate values
    #vals = []
    vals = Array{Union{Missing,Float64}}(undef, nTotal)
    ix = 1

    for Xcol = 1:ncolsX
        for (i, b) in enumerate(bases)
            b_nz = nonzeros(b)
            l = length(b_nz)

            vals[ix:ix+l-1] .= b_nz .* @view X[i, Xcol]
            ix = ix + l
            #push!(vals, )
        end
    end
    return vals

end
"""
$(SIGNATURES)
performs the actual time-expansion in a sparse way.

 - Get the non-timeexpanded designmatrix X from StatsModels.
 - evaluate the basisfunction kernel at each event
 - calculate the necessary rows, cols and values for the sparse matrix
 Returns SparseMatrixCSC 
"""

function time_expand(Xorg, term, tbl)
    # this is the predefined eventfield, usually "latency"
    tbl = DataFrame(tbl)
    onsets = Float64.(tbl[:, term.eventfields[1]])::Vector{Float64} # XXX if we have integer onsets, we could directly speed up matrix generation maybe?

    if typeof(term.eventfields) <: Array && length(term.eventfields) == 1
        bases = kernel.(Ref(term.basisfunction), onsets)
    else
        bases = kernel.(Ref(term.basisfunction), eachrow(tbl[!, term.eventfields]))
    end

    return time_expand(Xorg, term, onsets, bases)
end
function time_expand(Xorg, term, onsets, bases)
    ncolsBasis = size(kernel(term.basisfunction, 0), 2)::Int64
    X = reshape(Xorg, size(Xorg, 1), :) # why is this necessary?
    ncolsX = size(X)[2]::Int64






    rows = timeexpand_rows(onsets, bases, shiftOnset(term.basisfunction), ncolsX)
    cols = timeexpand_cols(term, bases, ncolsBasis, ncolsX)

    vals = timeexpand_vals(bases, X, size(cols), ncolsX)

    #vals = vcat(vals...)
    ix = rows .> 0 #.&& vals .!= 0.
    A = @views sparse(rows[ix], cols[ix], vals[ix])
    dropzeros!(A)

    return A
end

"""
Helper function to decide whether all bases have the same number of columns per event
"""
time_expand_allBasesSameCols(b::FIRBasis, bases, ncolBasis) = true # FIRBasis is always fast!
function time_expand_allBasesSameCols(basisfunction, bases, ncolsBasis)
    fastpath = true
    for b in eachindex(bases)
        if length(unique(length.(nzrange.(Ref(bases[b]), 1:ncolsBasis)))) != 1
            return false
        end
    end
    return true
end

"""
$(SIGNATURES)
coefnames of a TimeExpandedTerm concatenates the basis-function name with the kronecker product of the term name and the basis-function colnames. Separator is ' : '
Some examples for a firbasis:
        basis_313 : (Intercept) : 0.1
        basis_313 : (Intercept) : 0.2
        basis_313 : (Intercept) : 0.3
        ...
"""
function StatsModels.coefnames(term::TimeExpandedTerm)
    terms = coefnames(term.term)
    colnames = Unfold.colnames(term.basisfunction)
    name = Unfold.name(term.basisfunction)
    if typeof(terms) == String
        terms = [terms]
    end
    return name .* " : " .* kron(terms .* " : ", string.(colnames))
end

function termnames(term::TimeExpandedTerm)
    terms = coefnames(term.term)
    colnames = colnames(term.basisfunction)
    if typeof(terms) == String
        terms = [terms]
    end
    return vcat(repeat.([[t] for t in terms], length(colnames))...)
end


function colname_basis(term::TimeExpandedTerm)
    terms = coefnames(term.term)
    colnames = colnames(term.basisfunction)
    if typeof(terms) == String
        terms = [terms]
    end
    return repeat(colnames, length(terms))
end


function StatsModels.coefnames(terms::AbstractArray{<:FormulaTerm})
    return coefnames.(Base.getproperty.(terms, :rhs))
end




function Base.show(io::IO, d::AbstractDesignMatrix)
    println(io, "Unfold.DesignMatrix")
    println(io, "Formula: $(formulas(d))")

    sz_evts = isa(d.events, Vector) ? size.(d.events) : size(d.events)
    sz_modelmatrix =
        (isa(d.modelmatrix, Vector) | isa(d.modelmatrix, Tuple)) ? size.(d.modelmatrix) :
        size(d.modelmatrix)

    println(io, "\nSizes: modelmatrix: $sz_modelmatrix, events: $sz_evts")
    println(io, "\nuseful functions: formulas(d), modelmatrix(d), events(d)")
    println(io, "Fields: .formula, .modelmatrix, .events")
end
