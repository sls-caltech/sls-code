function [x, u, time, iters] = mpc_distributed(sys, x0, params)
% Inputs
%   sys     : LTISystem containing system matrices (A, B2) and Nx, Nu
%   x0      : Initial system state
%   params  : MPCParams containing parameters for mpc
% Outputs
%   x       : Next state if MPC input is used
%   u       : Current input as calculated by MPC
%   time    : Total runtime (Steps 4+6+8+11) per state
%   iters   : Total ADMM iters per state
%
% Note that we include the first state as a representative per-state
% measurement for runtime calculations

%% Setup
sanity_check_actuation(sys)

if params.has_coupling()
    params.sanity_check_alg_2();
    sanity_check_coupling(sys, params);
else
    params.sanity_check_alg_1();
end

% For ease of notation
Nx = sys.Nx; Nu = sys.Nu;
tFIR = params.tFIR_;
rho      = params.rho_;

maxIters     = params.maxIters_;
maxItersCons = params.maxItersCons_;

nVals = Nx*tFIR + Nu*(tFIR-1);

% Track runtime
time  = 0;

% SLS constraints
Eye = [eye(Nx); zeros(Nx*(tFIR-1),Nx)];
ZAB = get_sls_constraint(sys, tFIR);

% Get indices corresponding to rows / columns / localities
PsiSupp  = get_psi_sparsity(sys, params); % Toeplitz matrix
PhiSupp  = PsiSupp(:, 1:Nx);              % First block column
r   = assign_rows_phi(sys, tFIR);
c   = assign_cols_phi(sys);
s_r = get_row_locality(r, PhiSupp);
s_c = get_col_locality(c, PhiSupp);

% Constraints, costs, and coupling info
C     = build_cost_mtx(params);
K     = build_constr_mtx(sys, params);
cpIdx = get_coupling_indices(C, K);

% ADMM variables
Phi    = zeros(nVals, Nx);
Psi    = zeros(nVals, Nx);
Lambda = zeros(nVals, Nx);

nValsCoup = 0;
for i = 1:Nx
    for j = 1:length(r{i})
        row   = r{i}{j};     
        if length(cpIdx{row}) > 1 % there is coupling
            nValsCoup = nValsCoup+1;
        end
    end
end

Y_rows = cell(nValsCoup, 1);
Z_rows = cell(nValsCoup, 1);

coupled_r   = cell(Nx, 1);
coupled_s_r = cell(Nx, 1);
uncoupled_r = cell(Nx, 1);
uncoupled_s_r = cell(Nx, 1);

% Identify rows with coupling 
for i = 1:Nx
    j_c = 0; j_unc = 0;
    for j = 1:length(r{i})
        row   = r{i}{j};     
        if length(cpIdx{row}) <= 1 % there is only "self-coupling"
            j_unc = j_unc +1;
            uncoupled_r{i}{j_unc} = r{i}{j};
            uncoupled_s_r{i}{j_unc} = s_r{i}{j};
        else % there is coupling: initialize Y, Z
            j_c = j_c +1;
            coupled_r{i}{j_c} = r{i}{j};
            coupled_s_r{i}{j_c} = s_r{i}{j};
            Z_rows{row} = 0;
            for k = cpIdx{row}
                Y_rows{row}{k} = 0;
            end
        end
    end
end

% Column-wise partition SLS constraints and pre-calculate inverse
zabs  = cell(Nx, 1);
eyes  = cell(Nx, 1);
zabis = cell(Nx, 1); % inverse

for i = 1:Nx
    zab_     = ZAB(:, s_c{i}{1});
    zeroRows = find(all(zab_ == 0, 2));
    keepRows = setdiff(1:tFIR*Nx, zeroRows);
    zabs{i}  = ZAB(keepRows, s_c{i}{1});
    eyes{i}  = Eye(keepRows, c{i}{1});
    
    zabis{i} = zabs{i}'*pinv(zabs{i}*zabs{i}');
end

%% MPC
for iters=1:maxIters % ADMM (outer loop)
    Psi_prev = Psi;
    
    % Separate Psi, Lambda into rows (with sparsity)
    Psi_rows    = separate_rows(r, s_r, Psi);
    Lambda_rows = separate_rows(r, s_r, Lambda);
    
    % Solve for Phi
    Phi_rows = cell(nVals, 1);
    
    % UNCOUPLED ROWS:
    for i = 1:Nx
        if ~isempty(uncoupled_r{i})
            for j = 1:length(uncoupled_r{i})
                row   = uncoupled_r{i}{j};

                x_loc = x0(uncoupled_s_r{i}{j}); % observe local state
                cost_ = C(row, row);

                solverMode = params.solverMode_;

                if K(row, row) % has constraint
                    if row <= tFIR*Nx % state constraint
                        b1_ = params.stateUB_(i) / K(row, row);
                        b2_ = params.stateLB_(i) / K(row, row);
                    else % input constraint
                        inputIdx = find(sys.B2(i,:));
                        b1_ = params.inputUB_(inputIdx) / K(row, row);
                        b2_ = params.inputLB_(inputIdx) / K(row, row);
                    end
                    b1  = max(b1_,b2_); b2 = min(b1_,b2_); % in case of negative signs

                    if isempty(solverMode)
                        solverMode = MPCSolverMode.Explicit;
                    end

                else % no constraint, use closed form
                    solverMode = MPCSolverMode.ClosedForm;
                end

                if solverMode == MPCSolverMode.ClosedForm
                    if i == 1; tic; end
                    Phi_rows{row} = eqn_16a_closed(x_loc, Psi_rows{row}, Lambda_rows{row}, cost_, rho);
                    if i == 1; time = time + toc; end
                elseif solverMode == MPCSolverMode.Explicit
                    if i == 1; tic; end
                    Phi_rows{row} = eqn_16a_explicit(x_loc, Psi_rows{row}, Lambda_rows{row}, b1, b2, cost_, rho);
                    if i == 1; time = time + toc; end
                else % use solver
                    [Phi_rows{row}, solverTime] = eqn_16a_solver(x_loc, Psi_rows{row}, Lambda_rows{row}, b1, b2, cost_, rho);
                    if i == 1; time = time + solverTime; end
                end
            end
        end
    end
    
    % COUPLED ROWS:
    converged = true; % in case we have no coupled rows
    if ~isempty(coupled_r)
        
        for consIter=1:maxItersCons % ADMM consensus (inner loop)
            Z_prev_rows = Z_rows;

            % Step 4: Solve (20a) to get local Phi, X
            X_rows   = cell(nValsCoup, 1);

            for i = 1:Nx
                for j = 1:length(coupled_r{i})
                    row     = coupled_r{i}{j};
                    x_loc   = x0(coupled_s_r{i}{j});   % observe local state
                    cps     = cpIdx{row};       % coupling indices for this row
                    selfIdx = find(cps == row); % index of "self-coupling" term

                    cost_ = C(row, cps);
                    k_    = K(row, cps); % constraint

                    solverMode = params.solverMode_;

                    if ~all(k_ == 0) % has constraint
                        if row <= Nx*tFIR % is state
                            lb  = params.stateLB_(i);
                            ub  = params.stateUB_(i);
                        else % is input
                            inputIdx = find(sys.B2(i,:));
                            lb = params.inputLB_(inputIdx);
                            ub = params.inputUB_(inputIdx);
                        end

                        if isempty(solverMode)
                            solverMode = MPCSolverMode.UseSolver;
                        end
                    else % no constraint, use closed form
                        solverMode = MPCSolverMode.ClosedForm;
                    end

                    if solverMode == MPCSolverMode.ClosedForm
                        if i == 1; tic; end                        
                        [Phi_rows{row}, x_row] = eqn_20a_closed(x_loc, Psi_rows{row}, Lambda_rows{row}, Y_rows{row}(cps), Z_rows(cps), ...
                            cost_, selfIdx, params);
                        if i == 1; time = time + toc; end
                    elseif solverMode == MPCSolverMode.Explicit
                        mpc_error('There is no explicit mode for Algorithm 2!');
                    else % use solver
                        [Phi_rows{row}, x_row, solverTime] = eqn_20a_solver(x_loc, Psi_rows{row}, Lambda_rows{row}, Y_rows{row}(cps), Z_rows(cps), ...
                            cost_, k_, selfIdx, lb, ub, params);
                        if i == 1; time = time + solverTime; end
                    end

                    X_rows{row}             = zeros(nVals, 1);
                    X_rows{row}(cpIdx{row}) = x_row;
                end
            end

            % Step 6: Update Z (Step 5 implicitly done in this step)
            for i = 1:Nx
                if i == 1; tic; end
                for j = 1:length(coupled_r{i})
                    row = coupled_r{i}{j};
                    Z_rows{row} = 0;
                    for k = cpIdx{row}                                           
                        Z_rows{row} = Z_rows{row} + (X_rows{k}(row)+Y_rows{k}{row})/length(cpIdx{row});
                    end
                end
                if i == 1; time = time + toc; end
            end

            % Step 8: Update Y (Step 7 implicitly done in this step)
            for i = 1:Nx
                if i == 1; tic; end
                for j = 1:length(coupled_r{i})
                    row = coupled_r{i}{j};
                    for k = cpIdx{row}
                        Y_rows{row}{k} = Y_rows{row}{k} + X_rows{row}(k) - Z_rows{k};
                    end
                end
                if i == 1; time = time + toc; end
            end

            % Step 9: Check convergence of ADMM consensus
            converged = true;
            for i = 1:Nx
                for j = 1:length(coupled_r{i})
                    row = coupled_r{i}{j};
                    z_cp = zeros(nVals, 1);
                    for k = cpIdx{row}
                        z_cp(k) = Z_rows{k};
                    end

                    if ~check_convergence_cons(z_cp, X_rows{row}, Z_rows{row}, Z_prev_rows{row}, params)
                        converged = false;
                        break; % if one fails, can stop checking the rest
                    end
                end
            end

            if converged
                break; % exit ADMM consensus iterations
            end
        end

        if ~converged
            fprintf('ADMM consensus reached %d iters and did not converge\n', maxItersCons);
        end
        
    end 
    
    % Step 10: Build entire Phi matrix
    Phi = build_from_rows(r, s_r, Phi_rows, size(Phi));
    
    % Separate Phi, Lambda into columns
    Phi_cols    = separate_cols(c, s_c, Phi);
    Lambda_cols = separate_cols(c, s_c, Lambda);
    
    % Step 11: Solve (16b) to get local Psi
    Psi_cols = cell(Nx, 1);
    for i = 1:Nx
        if i == 1; tic; end
        Psi_cols{i} = eqn_16b(Phi_cols{i}, Lambda_cols{i}, zabs{i}, eyes{i}, zabis{i});
        if i == 1; time = time + toc; end
    end
    
    % Step 12: Build entire Psi matrix
    Psi = build_from_cols(c, s_c, Psi_cols, size(Psi));
    
    % Step 13: Update Lambda
    Lambda = Lambda + Phi - Psi;
    
    % Step 14: Check convergence of ADMM (outer loop)
    converged = true;
    for i = 1:Nx
        phi_      = [];
        psi_      = [];
        psi_prev_ = [];
        for j = 1:length(r{i})
            % Due to dimensionality issues, not stacking rows
            % Instead, just make one huge row
            % (since we're checking Frob norm, doesn't matter)
            phi_      = [phi_, Phi(r{i}{j}, s_r{i}{j})];
            psi_      = [psi_, Psi(r{i}{j}, s_r{i}{j})];
            psi_prev_ = [psi_prev_, Psi_prev(r{i}{j}, s_r{i}{j})];
        end
        
        if ~check_convergence(phi_, psi_, psi_prev_, params)
            converged = false;
            break; % if one fails, can stop checking the rest
        end
    end
    
    if converged
        break; % exit ADMM iterations
    end
end

if ~converged
    fprintf('ADMM reached %d iters and did not converge\n', maxIters);
end

% Compute control + state
u = Phi(1+Nx*tFIR:Nx*tFIR+Nu,:)*x0;
x = Phi(1+Nx:2*Nx,:)*x0; % since no noise, x_ref = x
end