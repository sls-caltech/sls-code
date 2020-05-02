clear all; close all; clc;

%% Algorithm 1 setup plant + parameters
rng(420);
sys1    = LTISystem;
sys1.Nx = 8; 
alpha = 0.8; rho = 1; actDens = 0.6; 
generate_dbl_stoch_chain(sys1, rho, actDens, alpha);
x01 = rand(sys1.Nx, 1);

params1 = MPCParams();
params1.locality_ = 3;
params1.tFIR_     = 5;
params1.tHorizon_ = 10;
params1.maxIters_ = 5000;
params1.rho_      = 1; 
params1.eps_p_    = 1e-3;
params1.eps_d_    = 1e-3;

params1.Q_ = eye(sys1.Nx);
params1.R_ = eye(sys1.Nu);

%% Algorithm 1, ClosedForm
params1.solnMode_ = MPCSolMode.ClosedForm;
[x, u, ~]       = mpc_algorithm_1(sys1, x01, params1);
[xVal, uVal, ~] = mpc_centralized(sys1, x01, params1);
printAndPlot(params1, x, u, xVal, uVal, 'Alg1, ClosedForm');

%% Algorithm 1, Explicit
params1.stateUpperbnd_ = 1.2;
params1.stateLowerbnd_ = -0.2;

params1.solnMode_ = MPCSolMode.Explicit;
[x, u, ~]       = mpc_algorithm_1(sys1, x01, params1);
[xVal, uVal, ~] = mpc_centralized(sys1, x01, params1);
printAndPlot(params1, x, u, xVal, uVal, 'Alg1, Explicit');

%% Algorithm 1, UseSolver
params1.stateUpperbnd_ = 1.2;
params1.stateLowerbnd_ = -0.2;

params1.solnMode_ = MPCSolMode.UseSolver;
[x, u, ~]       = mpc_algorithm_1(sys1, x01, params1);
[xVal, uVal, ~] = mpc_centralized(sys1, x01, params1);
printAndPlot(params1, x, u, xVal, uVal, 'Alg1, UseSolver');

%% Algorithm 2 setup plant + parameters
sys2    = LTISystem;
sys2.Nx = 4; 
alpha = 0.8; rho = 1; actDens = 0.5; 
generate_dbl_stoch_chain(sys2, rho, actDens, alpha);
x02 = rand(sys2.Nx, 1);

params2 = copy(params1);
params2.stateUpperbnd_ = []; % clear constraints
params2.stateLowerbnd_ = [];

params2.maxItersCons_ = 500;
params2.mu_           = 1;
params2.eps_x_        = 1e-3;
params2.eps_z_        = 1e-3;

Nx = sys2.Nx;
params2.Q_ = diag(ones(Nx,1)) + diag(-1/2*ones(Nx-2,1),2) + diag(-1/2*ones(Nx-2,1),-2);
params2.R_ = eye(sys2.Nu);

%% Algorithm 2, ClosedForm
params2.solnMode_ = MPCSolMode.ClosedForm;
[x, u, ~]       = mpc_algorithm_2(sys2, x02, params2);
[xVal, uVal, ~] = mpc_centralized(sys2, x02, params2);
printAndPlot(params2, x, u, xVal, uVal, 'Alg2, ClosedForm');

%% Algorithm 2, UseSolver
% Constraints
for i = 1:2:2*(Nx-1)
    K1(i,i)     = 1; 
    K1(i,i+2)   = -1;
    K1(i+1,i)   = -1; 
    K1(i+1,i+2) = 1;
end
K1            = K1(1:Nx,1:Nx); 
K1(Nx-1:Nx,:) = zeros(2,Nx);
  
Ksmall = zeros(2*Nx,Nx); j = 0;
for i = 1:2*Nx
    if mod(i,4) == 1 || mod(i,4) == 2
        j = j + 1;
        Ksmall(i,:) = K1(j,:);
    else
    end
end
params2.constrMtx_ = Ksmall;
params2.constrUpperbnd_ = 0.5;

params2.solnMode_ = MPCSolMode.UseSolver;
[x, u, ~]       = mpc_algorithm_2(sys2, x02, params2);
[xVal, uVal, ~] = mpc_centralized(sys2, x02, params2);
printAndPlot(params2, x, u, xVal, uVal, 'Alg2, UseSolver');

%% Local function to print values + plot graphs
function printAndPlot(params, x, u, xVal, uVal, myTitle)
    % Calculate costs + plot 
    tSim   = params.tHorizon_;
    obj    = get_cost_fn(params, x, u);
    objVal = get_cost_fn(params, xVal, uVal);

    % Print costs (sanity check: should be close)
    fprintf('Distributed cost: %f\n', obj);
    fprintf('Centralized cost: %f\n', objVal);

    figure()
    plot(1:tSim+1,xVal(1,:),'b',1:tSim+1,x(1,:),'*b')
    xlabel('Time');
    ylabel('State (1st only)');
    legend('Centralized', 'Distributed');
    title(myTitle);
end