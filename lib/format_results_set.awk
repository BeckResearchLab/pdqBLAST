{
	if (line == 0) {
		for (i = 1; i <= NF; ++i) {
			field[i] = $i;
			gsub("_", " ", field[i]);
			gsub("blast", "BLAST", field[i]);
		}
		fields = NF;
	} else{
		for (i = 1; i <= fields; ++i)
			data[line, i] = $i;
	}
	++line;
}
END {
	if (title != 0) {
		len = length(title);
		printf("%s ", title);
		for (i = len + 2; i < 79; ++i)
			printf("-");
		printf("\n");
	}
	for (i = 1; i < line; ++i) {
		for (j = 1; j <= fields; ++j) {
			printf("%20s : %s\n", field[j], data[i, j]);
		}
		if (i < line - 1) {
			for (j = 0; j < 79; ++j)
				printf("-");
			printf("\n");
		}
	}
}
