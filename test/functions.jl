
@testset "Function testing" begin

@testset ":Options" begin
    m = Model(solver=DefaultTestSolver(;traverse_strategy=:DBFS,obj_epsilon=0.5))

    v = [10,20,12,23,42]
    w = [12,45,12,22,21]
    @variable(m, x[1:5], Bin)

    @objective(m, Max, dot(v,x))

    @NLconstraint(m, sum(w[i]*x[i]^2 for i=1:5) <= 45)   

    JuMP.build(m)
    options = m.internalModel.options

    nd_options = Juniper.get_non_default_options(options)    
    @test nd_options[:obj_epsilon] == 0.5
    @test nd_options[:traverse_strategy] == :DBFS
    @test length(nd_options[:log_levels]) == 0
end

function option_not_available_t()
    m = Model(solver=DefaultTestSolver(;traverse_strategy=:DBS,obj_epsilon=0.5))
end
function option_not_available_b()
    m = Model(solver=DefaultTestSolver(;branch_strategy=:Pseudo,obj_epsilon=0.5))
end
function option_not_available()
    m = Model(solver=DefaultTestSolver(;branch=:Pseudo,obj_epsilon=0.5))
end
function option_no_mip_solver()
    m = Model(solver=DefaultTestSolver(;branch=:Pseudo,obj_epsilon=0.5,feasibility_pump=true))
    v = [10,20,12,23,42]
    w = [12,45,12,22,21]
    @variable(m, x[1:5], Bin)

    @objective(m, Max, dot(v,x))

    @NLconstraint(m, sum(w[i]*x[i]^2 for i=1:5) <= 45)   

    JuMP.build(m)
    return m.internalModel.options
end

@testset ":Option not available" begin
    @test_throws ErrorException option_not_available_t()
    @test_throws ErrorException option_not_available_b()
    opts = option_no_mip_solver()
    @test opts.feasibility_pump == false
    @test !isa(try option_not_available() catch ex ex end, Exception) 
end

@testset "Info/Table" begin
    m = Model(solver=DefaultTestSolver(;branch_strategy=:StrongPseudoCost,processors=2,
                                        strong_restart=true))

    v = [10,20,12,23,42]
    w = [12,45,12,22,21]
    @variable(m, x[1:5], Bin)

    @objective(m, Max, dot(v,x))

    @NLconstraint(m, sum(w[i]*x[i]^2 for i=1:5) <= 45)   
    
    JuMP.build(m)
    m = m.internalModel
    options = m.options

    @test !isa(try Juniper.print_info(m) catch ex ex end, Exception) 
    @test !isa(try Juniper.print_options(m;all=true) catch ex ex end, Exception) 
    @test !isa(try Juniper.print_options(m;all=false) catch ex ex end, Exception) 
    

    fields, field_chars = Juniper.get_table_config(options)
    ln = Juniper.get_table_header_line(fields, field_chars)
    @test length(ln) == sum(field_chars)
        
    start_time = time()
    tree = Juniper.init(start_time,m)
    tree.best_bound = 100
    node = Juniper.new_default_node(1,1,zeros(Int64,5),ones(Int64,5),zeros(Int64,5))
    step_obj = Juniper.new_default_step_obj(m,node)
    step_obj.counter = 1
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    @test length(fields) == length(field_chars)
    for i in 1:length(fields)
        fc = field_chars[i]
        f = string(fields[i])
        @test fc >= length(f)
    end
    # Test with incumbent
    tree.incumbent = Juniper.Incumbent(42,[0,0,0,0,1],:UserLimit,65)
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    @test length(fields) == length(field_chars)
    for i in 1:length(fields)
        fc = field_chars[i]
        f = string(fields[i])
        @test fc >= length(f)
    end
    @test length(fields) == length(tab_arr)
    @test length(tab_ln) == sum(field_chars)

    # test for diff
    tab_arr_new = copy(tab_arr)
    tab_arr_new[1] = 100
    @test Juniper.is_table_diff(fields, tab_arr, tab_arr_new) == true
    @test Juniper.is_table_diff(fields, tab_arr, tab_arr) == false
    
    # test if :Time not exists
    i = 1
    for f in fields
        if f == :Time
            deleteat!(fields,i)
            deleteat!(field_chars,i)
        end
        i+= 1
    end
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    tab_arr_new = copy(tab_arr)
    tab_arr_new[1] = 100
    @test Juniper.is_table_diff(field_chars, tab_arr, tab_arr_new) == true
    @test Juniper.is_table_diff(field_chars, tab_arr, tab_arr) == false

    # produce table line with high counter for nrestarts
    step_obj.counter = 100
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    idx_restarts = findfirst(fields .== :Restarts)
    @test tab_arr[idx_restarts] == "-"
    
    # normal gain gap
    step_obj.gain_gap = 0.05
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    idx_gain_gap = findfirst(fields .== :GainGap)
    @test tab_arr[idx_gain_gap] == "5.0%" || tab_arr[idx_gain_gap] == "5.00%"

    # Inf gain gap
    step_obj.gain_gap = Inf
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    idx_gain_gap = findfirst(fields .== :GainGap)
    @test tab_arr[idx_gain_gap] == "∞"

    # Huge gain gap
    step_obj.gain_gap = 123456789000
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    idx_gain_gap = findfirst(fields .== :GainGap)
    @test tab_arr[idx_gain_gap] == ">>"

    # very large gap
    tree.best_bound = 1000000
    tree.incumbent.objval = 1
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    idx_gap = findfirst(fields .== :Gap)
    @test tab_arr[idx_gap] == ">>"

    # way too long 
    fields, field_chars = Juniper.get_table_config(options)
    start_time = time()-123456789
    tab_ln, tab_arr = Juniper.get_table_line(2,tree,node,step_obj,start_time,fields,field_chars;last_arr=[])
    idx_time = findfirst(fields .== :Time)
    @test tab_arr[idx_time] == "t.l."
end

@testset "FP: Table config" begin
    mip_obj,nlp_obj,t, fields, field_chars = 5,2,2, [:MIPobj,:NLPobj,:Time], [20,20,10]
    ln, arr = Juniper.get_fp_table(mip_obj,nlp_obj,t, fields, field_chars)
    @test length(ln) == 50
    @test arr == ["5.0","2.0","2.0"] 
end

@testset "Random restarts" begin
    m = Model(solver=DefaultTestSolver(;branch_strategy=:StrongPseudoCost,processors=2,
    strong_restart=true))

    v = [10,20,12,23,42]
    w = [12,45,12,22,21]
    @variable(m, x[1:5], Int)
    setlowerbound(x[1], 0)
    setlowerbound(x[2], 0.5)
    setupperbound(x[3], 1)
    setupperbound(x[2], 1)

    @objective(m, Max, dot(v,x))

    @NLconstraint(m, sum(w[i]*x[i]^2 for i=1:5) <= 45)   

    JuMP.build(m)
    model = m.internalModel

    cont_restart = Juniper.generate_random_restart(model)
    @test length(cont_restart) == 5
    @test 0 <= cont_restart[1] <= 20
    @test 0.5 <= cont_restart[2] <= 1
    @test -19 <= cont_restart[3] <= 1
    @test -10 <= cont_restart[4] <= 10
    @test -10 <= cont_restart[5] <= 10
    

    disc_restart = Juniper.generate_random_restart(model; cont=false)
    @test length(disc_restart) == 5
    for i=1:5
        @test isapprox(round(disc_restart[i])-disc_restart[i],0,atol=1e-6)
    end

end

@testset "LSE matrix" begin
    m = Model(solver=DefaultTestSolver(;branch_strategy=:MostInfeasible,log_levels=[:All]))

    v = [10,20,12,23,42]
    w = [12,45,12,22,21]
    @variable(m, x[1:5], Int)
    @variable(m, y)

    @objective(m, Max, dot(v,x)+100*y)

    @NLconstraint(m, sum(w[i]*x[i]^2 for i=1:5) <= 45)   
    @constraint(m, sum(w[i]*x[i] for i=1:5) <= 25)   
    @constraint(m, sum(w[i]*x[i] for i=1:2)+1*y <= 10)   
    @constraint(m, 3*y <= 20)

    solve(m)
    
    model = m.internalModel
    
    complete_mat = Juniper.construct_complete_affine_matrix(model)
    @test complete_mat[1,:] == vcat(w, [0])
    @test complete_mat[2,:] == vcat(w[1:2],[0,0,0],[1])

    disc_mat = Juniper.construct_disc_affine_matrix(model; only_non_zero=false)
    @test disc_mat[1,:] == w
    @test disc_mat[2,:] == vcat(w[1:2],[0,0,0])
    @test disc_mat[3,:] == [0,0,0,0,0]

    disc_mat = Juniper.construct_disc_affine_matrix(model)
    @test disc_mat[1,:] == w
    @test disc_mat[2,:] == vcat(w[1:2],[0,0,0])
    @test size(disc_mat)[1] == 2
end

end