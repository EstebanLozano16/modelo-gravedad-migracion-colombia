################################################################################
# PROYECTO: Modelo de Gravedad de la Migración Venezolana en Colombia (2024).
# AUTOR: Juan Esteban Lozano Arcila,
################################################################################

# 1. CARGA DE LIBRERÍAS (Organizadas al inicio)
library(haven)     # Lectura de .sav
library(tidyverse) # Manipulación de datos
library(readxl)    # Lectura de Excel
library(sf)        # Datos espaciales
library(fixest)    # Modelos de gravedad (PPML)
library(geosphere) # Cálculos geográficos

# 2. CONFIGURACIÓN DE RUTAS (Usa rutas relativas para GitHub)
# Nota: En GitHub, el usuario debe colocar sus archivos en una carpeta llamada /data
input_path <- "data/" 

# 3. DEPURACIÓN DE DATOS MIGRATORIOS -------------------------------------------

# Lectura de flujos migratorios 2024 (Migración Colombia)
datos_raw <- read_sav(paste0(input_path, "ENTRADAS_Y_SALIDAS_PERSONAS_PAIS_2024.sav"))

base_migracion <- datos_raw %>% 
  filter(grepl("VENEZUELA", País_Nacionalidad, ignore.case = TRUE),
         Entrada_Salida == "Entradas") %>%
  # Clasificación de Tareas según CUOC 2024 (Basado en Dustmann 2025)
  mutate(
    Primer_Digito = substr(as.character(CODIGO_CUOC_2024_DANE), 1, 1),
    Tipo_Tarea = case_when(
      Primer_Digito %in% c("1", "2", "3") ~ "Abstracta",
      Primer_Digito %in% c("4", "5", "6", "7", "8", "9") ~ "Rutinaria",
      Primer_Digito == "0" ~ "Fuerzas Militares", 
      TRUE ~ "No Clasificado"
    )
  ) %>%
  group_by(CODIGO_DANE_MPIO_HOSPEDAJE, Ciudad_Hospedaje, Tipo_Tarea) %>%
  summarise(
    Total_Migrantes = sum(Total_Registros, na.rm = TRUE),
    Prop_Mujeres = sum(Sexo == "Femenino") / n(),
    .groups = 'drop'
  ) %>%
  filter(!is.na(CODIGO_DANE_MPIO_HOSPEDAJE), 
         !Tipo_Tarea %in% c("No Clasificado", "Fuerzas Militares"))

# 4. LIMPIEZA DE DATOS TERRITORIALES (TERRIDATA) -------------------------------

# A. Población 2024 (Suma de componentes para evitar duplicados)
df_poblacion <- read_excel(paste0(input_path, "TerriData_Dim2.xlsx")) %>%
  filter(Año == 2024, 
         !grepl("Porcentaje", `Unidad de Medida`, ignore.case = TRUE),
         !Indicador %in% c("Población total", "Población urbana", "Población rural")) %>%
  mutate(
    CODIGO_DANE_MPIO_HOSPEDAJE = str_pad(str_trim(`Código Entidad`), 5, pad = "0"),
    Valor = as.numeric(gsub(",", ".", gsub("[^0-9,]", "", as.character(`Dato Numérico`))))
  ) %>%
  group_by(CODIGO_DANE_MPIO_HOSPEDAJE) %>%
  summarise(Poblacion_Total_2024 = sum(Valor, na.rm = TRUE))

# B. Desempeño Municipal (MDM 2022)
df_mdm <- read_excel(paste0(input_path, "TerriData_Dim8.xlsx")) %>%
  filter(Año == 2022) %>%
  mutate(CODIGO_DANE_MPIO_HOSPEDAJE = str_pad(str_trim(`Código Entidad`), 5, pad = "0"),
         MDM_Texto = str_trim(as.character(`Dato Cualitativo`))) %>%
  distinct(CODIGO_DANE_MPIO_HOSPEDAJE, .keep_all = TRUE) %>%
  select(CODIGO_DANE_MPIO_HOSPEDAJE, MDM_Texto)

# C. Educación Superior (2023)
df_educ <- read_excel(paste0(input_path, "TerriData_Dim4.xlsx")) %>%
  filter(grepl("Tasa de tránsito inmediato a la educación superior", Indicador, ignore.case = TRUE),
         Año == 2023) %>%
  mutate(CODIGO_DANE_MPIO_HOSPEDAJE = str_pad(str_trim(`Código Entidad`), 5, pad = "0"),
         Valor_Educ = as.numeric(gsub(",", ".", gsub("[^0-9.]", "", as.character(`Dato Numérico`))))) %>%
  distinct(CODIGO_DANE_MPIO_HOSPEDAJE, .keep_all = TRUE) %>%
  select(CODIGO_DANE_MPIO_HOSPEDAJE, Valor_Educ)

# D. Servicios Públicos (Acueducto 2024)
df_serv <- read_excel(paste0(input_path, "TerriData_Dim3.xlsx")) %>%
  filter(Indicador == "Cobertura de acueducto (REC)", Año == 2024) %>%
  mutate(CODIGO_DANE_MPIO_HOSPEDAJE = str_pad(str_trim(`Código Entidad`), 5, pad = "0"),
         Cobertura_Acueducto = as.numeric(gsub(",", ".", as.character(`Dato Numérico`)))) %>%
  distinct(CODIGO_DANE_MPIO_HOSPEDAJE, .keep_all = TRUE) %>%
  select(CODIGO_DANE_MPIO_HOSPEDAJE, Cobertura_Acueducto)

# E. PIB Departamental (2023) para el reparto
df_pib_dep <- read_excel(paste0(input_path, "TerriData_Dim12.xlsx")) %>%
  filter(Año == 2023, str_trim(Indicador) == "PIB") %>%
  mutate(COD_DEPTO = substr(str_pad(`Código Entidad`, 5, pad = "0"), 1, 2),
         PIB_Dep_2023 = as.numeric(gsub(",", ".", gsub("[^0-9,]", "", as.character(`Dato Numérico`))))) %>%
  select(COD_DEPTO, PIB_Dep_2023) %>%
  distinct()

# 5. ESTIMACIÓN DEL PIB MUNICIPAL VÍA PCA --------------------------------------

base_consolidada <- df_poblacion %>%
  left_join(df_mdm, by = "CODIGO_DANE_MPIO_HOSPEDAJE") %>%
  left_join(df_educ, by = "CODIGO_DANE_MPIO_HOSPEDAJE") %>%
  left_join(df_serv, by = "CODIGO_DANE_MPIO_HOSPEDAJE") %>%
  drop_na()

# Creación de Dummies para el PCA
df_pca_input <- base_consolidada %>%
  mutate(d_Ciudades = ifelse(grepl("Ciudades", MDM_Texto), 1, 0),
         d_G1 = ifelse(grepl("G1", MDM_Texto), 1, 0),
         d_G2 = ifelse(grepl("G2", MDM_Texto), 1, 0),
         d_G3 = ifelse(grepl("G3", MDM_Texto), 1, 0),
         d_G4 = ifelse(grepl("G4", MDM_Texto), 1, 0),
         d_G5 = ifelse(grepl("G5", MDM_Texto), 1, 0)) %>%
  select(Valor_Educ, Cobertura_Acueducto, starts_with("d_"))

pca_final <- prcomp(df_pca_input, center = TRUE, scale. = TRUE)

# Inversión de signo e índice positivo (Multiplicador de riqueza)
base_consolidada$Indice_Capacidad <- pca_final$x[, 1] * -1
base_consolidada <- base_consolidada %>%
  mutate(Indice_Positivo = (Indice_Capacidad - min(Indice_Capacidad)) / 
           (max(Indice_Capacidad) - min(Indice_Capacidad)) + 0.1,
         COD_DEPTO = substr(CODIGO_DANE_MPIO_HOSPEDAJE, 1, 2)) %>%
  left_join(df_pib_dep, by = "COD_DEPTO") %>%
  group_by(COD_DEPTO) %>%
  mutate(Peso_Relativo = Poblacion_Total_2024 * Indice_Positivo,
         PIB_Municipal_Est = PIB_Dep_2023 * (Peso_Relativo / sum(Peso_Relativo))) %>%
  ungroup()

# 6. CÁLCULO DE DISTANCIA GEOGRÁFICA (SHP) -------------------------------------

municipios_shp <- st_read(paste0(input_path, "MGN_ADM_MPIO_GRAFICO.shp")) %>%
  st_transform(4326) %>%
  mutate(geometry = st_make_valid(geometry),
         centroide = st_centroid(geometry),
         lon = st_coordinates(centroide)[,1],
         lat = st_coordinates(centroide)[,2])

# Punto Cúcuta (EPSG: 9377 para precisión en metros)
coords_cucuta <- municipios_shp %>% filter(mpio_cdpmp == "54001") %>% st_geometry()
shp_proyectado <- st_transform(municipios_shp, 9377)
cucuta_proyectado <- st_transform(coords_cucuta, 9377)

municipios_shp$distancia_km <- as.numeric(st_distance(shp_proyectado, cucuta_proyectado)) / 1000

df_distancias <- municipios_shp %>% 
  st_drop_geometry() %>%
  select(CODIGO_DANE_MPIO_HOSPEDAJE = mpio_cdpmp, distancia_km)

# 7. MODELO DE GRAVEDAD FINAL (PPML) -------------------------------------------

base_final <- base_migracion %>%
  left_join(base_consolidada, by = "CODIGO_DANE_MPIO_HOSPEDAJE") %>%
  left_join(df_distancias, by = "CODIGO_DANE_MPIO_HOSPEDAJE") %>%
  drop_na(distancia_km, PIB_Municipal_Est) %>%
  mutate(log_Distancia = log(distancia_km + 1),
         log_PIB = log(PIB_Municipal_Est),
         MDM_Factor = relevel(factor(MDM_Texto), ref = "Ciudades"))

# Regresiones
reg_total <- fepois(Total_Migrantes ~ log_Distancia + log_PIB + Valor_Educ + MDM_Factor, 
                    data = base_final)

reg_dustmann <- fepois(Total_Migrantes ~ log_Distancia + log_PIB + Valor_Educ + MDM_Factor, 
                       split = ~Tipo_Tarea, data = base_final)

# Tabla de resultados
etable(reg_total, reg_dustmann, 
       headers = c("Total", "Abstracta", "Rutinaria"),
       dict = c(log_Distancia = "Log Distancia", log_Poblacion = "Log Población", Valor_Educ = "% Ed. Superior"))