clear; close all; clc; 

% specify system matrices
sys    = LTISystem;
sys.Nx = 10; sys.Nw = 10; 

% generate sys.A, sys.B2
alpha = 0.2; rho = 1; actDens = 1;
generate_dbl_stoch_chain(sys, rho, actDens, alpha); 

sys.Nz  = sys.Nu + sys.Nx;
sys.B1  = eye(sys.Nx); 
sys.C1  = [speye(sys.Nx); sparse(sys.Nu, sys.Nx)];
sys.D11 = sparse(sys.Nz, sys.Nw);
sys.D12 = [sparse(sys.Nx, sys.Nu); speye(sys.Nu)];
sys.sanity_check();

% simulation setup
simParams           = SimParams;
simParams.tSim_     = 25;
simParams.w_        = zeros(sys.Nx, simParams.tSim_); % disturbance
simParams.w_(floor(sys.Nx/2), 1) = 10;

%% (1) basic sls (centralized controller)
slsParams1    = SLSParams();
slsParams1.T_ = 20;

slsParams1.add_objective(SLSObjective.H2, 1); % H2 objective, coefficient = 1

clMaps1  = state_fdbk_sls(sys, slsParams1);
ctrller1 = Ctrller.ctrller_from_cl_maps(clMaps1);

[x1, u1] = simulate_state_fdbk(sys, ctrller1, simParams);
plot_heat_map(x1, sys.B2*u1, 'Centralized');

%% (2) localized and delayed sls
slsParams2    = SLSParams();
slsParams2.T_ = 20;

slsParams2.add_objective(SLSObjective.H2, 1); % H2 objective, coefficient = 1
slsParams2.add_constraint(SLSConstraint.ActDelay, 1); % actuation delay = 1
slsParams2.add_constraint(SLSConstraint.CommSpeed, 2); % comm speed = 2x propagation speed 
slsParams2.add_constraint(SLSConstraint.Locality, 3); % locality = 3-hops

clMaps2  = state_fdbk_sls(sys, slsParams2);
ctrller2 = Ctrller.ctrller_from_cl_maps(clMaps2);

[x2, u2] = simulate_state_fdbk(sys, ctrller2, simParams);
plot_heat_map(x2, sys.B2*u2, 'Loc + Delayed');

%% (3) approximate localized and delayed sls
slsParams3    = SLSParams();
slsParams3.T_ = 20;

slsParams3.add_objective(SLSObjective.H2, 1); % H2 objective, coefficient = 1
slsParams3.add_constraint(SLSConstraint.ActDelay, 1); % actuation delay = 1
slsParams3.add_constraint(SLSConstraint.CommSpeed, 1); % comm speed = 2x propagation speed 
slsParams3.add_constraint(SLSConstraint.Locality, 3); % locality = 3-hops

slsParams3.approx_      = true;
slsParams3.approxCoeff_ = 1e3;

clMaps3  = state_fdbk_sls(sys, slsParams3);
ctrller3 = Ctrller.ctrller_from_cl_maps(clMaps3);

[x3, u3] = simulate_state_fdbk(sys, ctrller3, simParams);
plot_heat_map(x3, sys.B2*u3, 'Approx Loc + Delayed');
