# Custom Solvers

### Setup some data

```@Example main
using Unfold
include(joinpath(dirname(pathof(MyModule)), "test/test_utilities") ) # to load data
dat, evts = loadtestdata("test_case_3b");

basisfunction = firbasis(τ=(-0.4,.8),sfreq=50,name="stimulus")
f  = @formula 0~1+conditionA+conditionB
bfDict = Dict(Any=>(f,basisfunction))

```

### Custom Solver with standard error
```@Example main
se_solver =(x,y)->Unfold.solver_default(x,y,stderror=true)
m = Unfold.fit(UnfoldLinearModel,bfDict,evts,data,solver=se_solver)
results =coeftable(m)
#plot_results(results) # => Wait with plotting till UnfoldPlots.jl and Unfold.jl is registered => Wait for overhall
```
!!! Warning Use single-subject SE on your own risk. Because EEG data are autocrrelated YOUR SE WILL BE TOO SMALL!

### Back2Back regression
```@Example main
b2b_solver = (x, y) -> Unfold.solver_b2b(x, y,cross_val_reps = 5)
m = Unfold.fit(UnfoldLinearModel, f, events, beta, times, solver=b2b_solver)
results = coeftable(m)

#plot_results(results) # => Wait with plotting till UnfoldPlots.jl and Unfold.jl is registered => Wait for overhall

```
