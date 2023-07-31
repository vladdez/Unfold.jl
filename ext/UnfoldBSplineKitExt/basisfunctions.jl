
Unfold.splinebasis(; τ, sfreq, nsplines, name) = Unfold.splinebasis(τ, sfreq, nsplines, name)
Unfold.splinebasis(τ, sfreq, nsplines) = Unfold.splinebasis(τ, sfreq, nsplines, "basis_" * string(rand(1:10000)))

shiftOnset(basis::Union{SplineBasis,FIRBasis}) = basis.shiftOnset

function Unfold.splinebasis(τ, sfreq, nsplines, name::String)
    τ = Unfold.round_times(τ, sfreq)
    times = range(τ[1], stop = τ[2], step = 1 ./ sfreq)
    kernel = e -> splinekernel(e, times, nsplines - 2)

    shiftOnset = Int64(floor(τ[1] * sfreq))
    colnames = spl_breakpoints(times, nsplines)
    return SplineBasis(kernel, colnames, times, name, shiftOnset)
end




function spl_breakpoints(times, nsplines)
    # calculate the breakpoints, evenly spaced
    return collect(range(minimum(times), stop = maximum(times), length = nsplines))
end

function splinekernel(e, times, nsplines)
    breakpoints = spl_breakpoints(times, nsplines)
    basis = BSplineKit.BSplineBasis(BSplineOrder(4), breakpoints)  # 4= cubic
    return sparse(splFunction(times, basis))
end