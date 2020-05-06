function [x_nxt, u] = mpc_glyco(sys, tFIR, x_lb, u_ub, xt, x_ref)
% Note that these are "x, u" in the local sense of mpc
% In the bilophila example, they are y and u_tilde (shifted coordinates)

Nx = sys.Nx; Nu = sys.Nu; A = sys.A; B = sys.B2;

RLoc = ones(Nx, Nx); % no sparsity constraint
MLoc = [0 1;
        0 1];

count = 0;
for k = 1:tFIR
    RSupp{k} = RLoc;
    MSupp{k} = MLoc;
    count = count + sum(sum(RSupp{k})) + sum(sum(MSupp{k}));
end

cvx_begin

variable X(count)
expression Rs(Nx, Nx, tFIR)
expression Ms(Nu, Nx, tFIR)
   
R = cell(tFIR, 1);
M = cell(tFIR, 1);

for t = 1:tFIR
    R{t} = Rs(:,:,t); M{t} = Ms(:,:,t); 
end

[R, M] = add_sparse_constraints(R, M, RSupp, MSupp, X, tFIR);

objective = 0;

state_pen = 1;
input_pen = 0.2;
for k = 1:tFIR
    % state constraint
    objective = objective + state_pen*(R{k}*xt-x_ref)'*(R{k}*xt-x_ref);
    % actuation constraint
    objective = objective + input_pen*(M{k}*xt)'*(M{k}*xt);
end

minimize(objective)
subject to

% Achievability constraints
R{1} == eye(Nx); 
for k=1:tFIR-1
    R{k+1} == A*R{k} + B*M{k};
end

for k=1:tFIR
     M{k}*xt <= u_ub;
     R{k}*xt >= x_lb;
end

cvx_end

u     = M{1}*xt;
x_nxt = R{2}*xt;

end
