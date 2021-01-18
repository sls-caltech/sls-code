function [x, u, time, iters] = sls_mpc_per_time(sys, x0, params)
% Call this function once per time-step with the desired system / params
% Allows some time-varying systems and constraints
%
% Inputs
%   sys     : LTISystem containing system matrices (A, B2) and Nx, Nu 
%   x0      : Starting system state
%   params  : MPCParams containing parameters for mpc
% Outputs
%   x       : Next state if MPC input is used
%   u       : Current input as calculated by MPC
%   time    : Total runtime per state
%   iters   : Total ADMM iters per state (for distributed MPC only)

iters = [];

if params.mode_ == MPCMode.Centralized
    if params.accounts_for_disturbance() % robust MPC    
        [x, u, time] = rmpc_centralized(sys, x0, params);
    else
        [x, u, time] = mpc_centralized(sys, x0, params);
    end
elseif params.mode_ == MPCMode.Distributed
    % Implementation of distributed MPC currently requires
    %  1. One actuator per subsystem
    %  2. Actuator indices should be a strictly increasing
    %     function of the subsystem indices they correspond to
    %  Example: B2 = [0 0 1;
    %                [0 1 0] violates (2)
    %           since actuator 3 corresponds to subsystem 1
    %           but   actuator 2 corresponds to subsystem 2
    %  B2 = [0 1 0;
    %       [0 0 1] will work

    lastActIdx = 0;
    for row=1:sys.Nu
        if length(find(sys.B2(row,:))) > 1
            mpc_error('Maximum one actuator per subsystem');
        end
        if find(sys.B2(row,:)) <= lastActIdx
            mpc_error('sys.B2 has unsupported sparsity pattern');
        end
        lastActIdx = find(sys.B2(row,:));
    end

    if ~params.has_coupling() % no coupling
        if params.accounts_for_disturbance()
            if params.has_state_cons() || params.has_input_cons() % Bounds specified; use robust mpc
                [x, u, time, iters] = rmpc_algorithm_1(sys, x0, params);
            else
                mpc_warning('Disturbance was specified but no state/input bounds apply.\nDisregarding disturbance and using standard (non-robust) MPC');
                [x, u, time, iters] = mpc_algorithm_2(sys, x0, params);
            end
        else
            [x, u, time, iters] = mpc_algorithm_2(sys, x0, params);
        end
    else % has coupling
        if params.accounts_for_disturbance()
            mpc_error('Robust MPC does not currently support coupled objectives or constraints');
        end

        Comms_Adj  = abs(sys.A) > 0;
        % sparsity patterns given by locality constraint
        StateSupp  = Comms_Adj^(params.locality_-1) > 0;
        InputSupp  = (abs(sys.B2)' * StateSupp * abs(sys.B2)) > 0;

        Comms_Cost_State = abs(params.QSqrt_) > 0;
        if ~isempty(find(StateSupp - Comms_Cost_State < 0, 1))
            mpc_error('State cost coupling violates locality!');
        end

        Comms_Cost_Input = abs(params.RSqrt_) > 0;
        if ~isempty(find(InputSupp - Comms_Cost_Input < 0, 1))
            mpc_error('Input cost coupling violates locality!');
        end

        if params.has_state_cons()
           Comms_Cons_State = abs(params.stateConsMtx_) > 0;
           if ~isempty(find(StateSupp - Comms_Cons_State < 0, 1))
               mpc_error('State constraint coupling violates locality!');
           end 
        end

        if params.has_input_cons()
            Comms_Cons_Input = abs(params.inputConsMtx_) > 0;
            if ~isempty(find(InputSupp - Comms_Cons_Input < 0,1))
                mpc_error('Input constraint coupling violates locality!');
            end
        end

        [x, u, time, iters] = mpc_algorithm_2(sys, x0, params);
    end
else
    mpc_error('Unrecognized MPC mode specified!');
end    
end