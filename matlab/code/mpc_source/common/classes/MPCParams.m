classdef MPCParams < matlab.mixin.Copyable
    % Contains parameters for MPC problems
    
    properties
        d_;        % locality
        
        tFIR_;     % order of controller (# spectral components)
        tHorizon_; % MPC time horizon
                
        maxIters_; % maximum allowed iterations for ADMM 
        rho_;      % ADMM update step size
        
        % determines exit conditions at Step 9 (Alg1) / Step 14 (Alg2)
        eps_p_; % convergence criterion for ||Phi(k+1) - Psi(k+1)|| 
        eps_d_; % convergence criterion for ||Psi(k+1) - Psi(k)||
        
        % Algorithm 2 only ----------------------------------------

        maxItersCons_; % maximum allowed iterations for ADMM consensus
        mu_;           % ADMM consensus update step size

        % determines exit conditions at Step 9 (Alg2)
        eps_x_; % convergence criterion for ||X(n+1) - Z(n+1)||
        eps_z_; % convergence criterion for ||Z(n+1) - Z(n)||
    end
    
    methods
      function sanity_check_alg_1(obj)
          e1 = isempty(obj.d_);
          e2 = isempty(obj.tFIR_);
          e3 = isempty(obj.tHorizon_);
          e4 = isempty(obj.maxIters_);
          e5 = isempty(obj.rho_);
          e6 = isempty(obj.eps_p_);
          e7 = isempty(obj.eps_d_);
          
          if (e1 || e2 || e3 || e4 || e5 || e6 || e7)
              sls_error('One or more required parameters is missing!')
          end
      end
      
      function sanity_check_alg_2(obj)
          sanity_check_alg_1(obj);
          
          e1 = isempty(obj.maxItersCons_);
          e2 = isempty(obj.mu_);
          e3 = isempty(obj.eps_x_);
          e4 = isempty(obj.eps_z_);
          
          if (e1 || e2 || e3 || e4)
              sls_error('One or more required parameters is missing!')
          end
          
      end
    end
end