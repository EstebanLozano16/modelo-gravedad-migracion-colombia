# Análisis de la Migración Venezolana en Colombia: Un Enfoque de Gravedad

Este repositorio contiene el desarrollo de un **Modelo de Gravedad** aplicado al flujo migratorio de venezolanos hacia los municipios de Colombia durante el año 2024. El estudio se centra en identificar cómo la distancia geográfica y la capacidad económica de los destinos influyen en la localización de los migrantes según su perfil laboral.

##  Características del Modelo
- **Estrategia de Identificación:** Uso de la distancia geodésica al Puente Internacional Simón Bolívar (Cúcuta) como factor de fricción espacial.
- **Estimación de PIB Municipal:** Ante la carencia de datos oficiales de PIB a nivel municipal para 2024, se implementó un **Análisis de Componentes Principales (PCA)** sobre variables de infraestructura (acueducto), capital humano y la Medición de Desempeño Municipal (MDM) para realizar un *downscaling* del PIB departamental.
- **Marco Teórico:** Inspirado en la metodología de **Dustmann, Otten, Schönberg & Stuhler (2025)**, segmentando el flujo en tareas **Abstractas (Skilled)** y **Rutinarias (Manuales)**.
- **Método Estadístico:** Estimador **PPML (Poisson Pseudo-Maximum Likelihood)** para manejar la sobredispersión de los datos y garantizar la consistencia de las elasticidades.

##  Hallazgos Principales
- Se confirmó la validez de la Ley de Gravedad con un coeficiente de distancia negativo y significativo.
- Los trabajadores con perfiles **Abstractos** muestran una mayor sensibilidad a la calidad del capital humano local (educación superior).
- El modelo alcanzó un **Pseudo R² de 0.82**, demostrando un alto poder predictivo de las variables seleccionadas.

##  Visualización de Datos
### Matriz de Correlación
A continuación, se presenta la relación entre las variables de masa (Población, PIB) y la fricción (Distancia).

![Matriz de Correlación](matriz%20de%20correlacion.png)
### Efecto de la Distancia
Relación logarítmica que demuestra el decaimiento del flujo migratorio a medida que aumenta la distancia desde la frontera.

![Gráfico de Distancia](graficodistanciamigracion.png)
