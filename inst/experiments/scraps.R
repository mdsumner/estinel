tar_load(dsn_table)
dplyr::arrange(dsn_table, desc(solarday)) |> print(n = 50)

which(is.na(dsn_table$outfile))
c(641, 2293, 3243, 3244, 3877, 4952, 5625, 6876, 7142, 8300, 9097, 9323, 9769)



group_table <- dplyr::filter(bg, tar_group == unique(tar_group)[5])
(dsn_table1 <- build_image_dsn(group_table, res = resolution, rootdir = rootdir))$assets[[1]]$red




