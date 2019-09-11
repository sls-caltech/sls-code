%% choose the system you want to work with
setup1;

%% sandbox
Tc = 4;
slsOuts_alt = find_alt_impl(sys, slsParams, slsOuts, Tc, 'approx');

s_a{1}  = slsOuts_alt;
zThresh = 1e-6;
met     = AltImplMetrics([Tc], zThresh);
met     = calc_mtx_metrics(met, sys, slsParams, slsOuts, s_a);
met     = calc_cl_metrics(met, sys, simParams, slsParams, slsOuts, s_a, [], '');
met % output metrics

%% find new implementations Rc, Mc
Tcs = [2:8];

% slsOuts_alts{i} contains alternate implementation for Tc=Tcs(i)
slsOuts_alts = cell(length(Tcs), 1);

for i=1:length(Tcs)
    Tc              = Tcs(i);
    slsOuts_alts{i} = find_alt_impl(sys, slsParams, slsOuts, Tc, 'approx');
end

disp(['Statuses:', print_statuses(slsOuts_alts)]); % check solver statuses

%% calculate stats & generate plots
savepath = 'C:\Users\Lisa\Desktop\caltech\research\implspace\tmp\';
plotTcs  = [2];

zThresh = 1e-6;
met     = AltImplMetrics(Tcs, zThresh);

% calculate matrix-specific metrics
met = calc_mtx_metrics(met, sys, slsParams, slsOuts, slsOuts_alts);

% calculate closed-loop metrics and plot select heat maps
met = calc_cl_metrics(met, sys, simParams, slsParams, slsOuts,...
                      slsOuts_alts, plotTcs, savepath);

% plot metrics
plot_metrics(met, savepath);