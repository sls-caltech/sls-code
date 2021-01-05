classdef MPCParams < matlab.mixin.Copyable
    % Contains parameters for MPC problems
    
    properties
        % Centralized or distributed
        mode_;
        
        % Algorithm 1 and 2 ---------------------------------------       
        locality_;  % locality (d)
        
        tFIR_;      % order of controller (# spectral components)               
        maxIters_;  % maximum allowed iterations for ADMM 
        rho_;       % ADMM update step size
        
        % determines exit conditions at Step 9 (Alg1) / Step 14 (Alg2)
        eps_p_; % convergence criterion for ||Phi(k+1) - Psi(k+1)|| 
        eps_d_; % convergence criterion for ||Psi(k+1) - Psi(k)||
        
        QSqrt_; % penalty for state (square-root)
        RSqrt_; % penalty for input (square-root)

        % Algorithm 2 only ----------------------------------------
        maxItersCons_; % maximum allowed iterations for ADMM consensus
        mu_;           % ADMM consensus update step size

        % determines exit conditions at Step 9 (Alg2)
        eps_x_; % convergence criterion for ||X(n+1) - Z(n+1)||
        eps_z_; % convergence criterion for ||Z(n+1) - Z(n)||
     
        % Optional params for constraints -------------------------
        stateConsMtx_;
        inputConsMtx_;
        
        stateUB_; % upper bound on stateConsMtx_ * state
        stateLB_; % lower bound on stateConsMtx_ * state
        
        inputUB_; % upper bound on inputConsMtx_ * input
        inputLB_; % lower bound on inputConsMtx_ * input
        
        % Robust MPC parameters -----------------------------------
        distConsMtx_;
        
        distUB_; % upper bound on distConsMtx_ * disturbance
        distLB_; % lower bound on distConsMtx_ * disturbance
    end

    methods        
      function sanity_check_params_1(obj)
          e1  = isempty(obj.locality_);
          e2  = isempty(obj.tFIR_);
          e3  = isempty(obj.maxIters_);
          e4  = isempty(obj.rho_);
          e5  = isempty(obj.eps_p_);
          e6  = isempty(obj.eps_d_);
          e7  = isempty(obj.QSqrt_);
          e8  = isempty(obj.RSqrt_);
          
          if (e1 || e2 || e3 || e4 || e5 || e6 || e7 || e8)
              mpc_error('One or more required parameters is missing!')
          end
      end
      
      function sanity_check_params_2(obj)
          sanity_check_params_1(obj);
          
          e1 = isempty(obj.maxItersCons_);
          e2 = isempty(obj.mu_);
          e3 = isempty(obj.eps_x_);
          e4 = isempty(obj.eps_z_);          
          
          if (e1 || e2 || e3 || e4)
              mpc_error('One or more required parameters is missing!')
          end 

      end
      
      function sanity_check_state_cons(obj)
          hasStateMtx = ~isempty(obj.stateConsMtx_);
          hasStateUB  = ~isempty(obj.stateUB_);
          hasStateLB  = ~isempty(obj.stateLB_);

          if hasStateMtx && ~hasStateUB && ~hasStateLB
              mpc_error('State constraint matrix was specified with no corresponding bounds!');
          elseif ~hasStateMtx && (hasStateUB || hasStateLB)
              mpc_error('State bounds were specified with no corresponding matrix!');
          end
          
          % Note: in theory it's possible to have constraint matrices
          %       of arbitrary size, but here we limit # of constraints
          %       to # of subsystems           
          if hasStateMtx && ~isequal(size(obj.stateConsMtx_), size(obj.QSqrt_))
              mpc_error('State constraint matrix is wrong size! Expect Nx by Nx');
          end
    
          % If only UB or only LB specified, populate other with Inf/-Inf
          if hasStateMtx && ~hasStateUB
              obj.stateUB_ = Inf;
          elseif hasStateMtx && ~hasStateLB
              obj.stateLB_ = -Inf;
          end
      end

      function sanity_check_input_cons(obj)
          hasInputMtx = ~isempty(obj.inputConsMtx_);
          hasInputUB  = ~isempty(obj.inputUB_);
          hasInputLB  = ~isempty(obj.inputLB_);

          if hasInputMtx && ~hasInputUB && ~hasInputLB
              mpc_error('Input constraint matrix was specified with no corresponding bounds!');
          elseif ~hasInputMtx && (hasInputUB || hasInputLB)
              mpc_error('Input bounds were specified with no corresponding matrix!');
          end

          % Note: in theory it's possible to have constraint matrices
          %       of arbitrary size, but here we limit # of constraints
          %       to # of inputs
          if hasInputMtx && ~isequal(size(obj.inputConsMtx_), size(obj.RSqrt_))
              mpc_error('Input constraint matrix is wrong size! Expect Nu by Nu');
          end

          % If only UB or only LB specified, populate other with Inf/-Inf
          if hasInputMtx && ~hasInputUB
              obj.inputUB_ = Inf;
          elseif hasInputMtx && ~hasInputLB
              obj.inputLB_ = -Inf;
          end
      end         
      
      function sanity_check_dist_cons(obj)
          hasdistMtx = ~isempty(obj.distConsMtx_);
          hasdistUB  = ~isempty(obj.distUB_);
          hasdistLB  = ~isempty(obj.distLB_);

          % Need upper AND lower bounds on disturbance (otherwise unbounded)
          if hasdistMtx && (~hasdistUB || ~hasdistLB) 
              mpc_error('Disturbance constraint matrix was specified with no corresponding bounds!');
          elseif ~hasdistMtx && (hasdistUB || hasdistLB)
              mpc_error('Disturbance bounds were specified with no corresponding matrix!');
          end
          
          % Note: in theory it's possible to have constraint matrices
          %       of arbitrary size, but here we limit # of constraints
          %       to # of subsystems           
          if hasdistMtx && ~isequal(size(obj.distConsMtx_), size(obj.QSqrt_))
              mpc_error('Disturbance constraint matrix is wrong size! Expect Nx by Nx');
          end
      end              
      
      function sanity_check_alg_1(obj)
          sanity_check_params_1(obj);
          sanity_check_state_cons(obj);
          sanity_check_input_cons(obj);
      end
      
      function sanity_check_alg_2(obj)
          sanity_check_params_2(obj);
          sanity_check_state_cons(obj);
          sanity_check_input_cons(obj);
      end
      
      function sanity_check_cent(obj)
          e1  = isempty(obj.locality_);
          e2  = isempty(obj.tFIR_);
          e3  = isempty(obj.QSqrt_);
          e4  = isempty(obj.RSqrt_);

          if (e1 || e2 || e3 || e4)
              mpc_error('One or more required parameters is missing!')
          end 
          
          sanity_check_state_cons(obj);
          sanity_check_input_cons(obj);
          sanity_check_dist_cons(obj);
      end          
          
      function hasStateCons = has_state_cons(obj)
          hasStateCons = ~isempty(obj.stateConsMtx_);
      end
      
      function hasInputCons = has_input_cons(obj)
          hasInputCons = ~isempty(obj.inputConsMtx_);
      end
      
      function accForDist = accounts_for_disturbance(obj)
          accForDist = ~isempty(obj.distConsMtx_);
      end
      
      function hasCoupling = has_coupling(obj)
          % at least one non-diagonal cost / constraint matrix
          hasCoupling = ~(isdiag(obj.QSqrt_) && isdiag(obj.RSqrt_) && isdiag(obj.stateConsMtx_) && isdiag(obj.inputConsMtx_));
      end
      
    end
end