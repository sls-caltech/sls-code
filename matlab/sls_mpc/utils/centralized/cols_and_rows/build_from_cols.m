function M = build_from_cols(c, s_c, M_cols, M_size)

M = zeros(M_size);

for i = 1:length(c)
    for j = 1:length(c{i})
        col = c{i}{j};
        M(s_c{i}{j}, col) = M_cols{col};
    end
end

end