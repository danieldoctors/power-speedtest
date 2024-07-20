# Definir los archivos de entrada y salida
$domainsFile = "domains.txt"
$metricsFile = "metrics.txt"
$outputFile = "pagespeed_results.csv"

# Leer los dominios y las métricas del archivo de texto
$domains = Get-Content $domainsFile
$metrics = Get-Content $metricsFile

# Crear una lista para almacenar los resultados
$results = @()

# Función para obtener el valor de una métrica anidada
function Get-MetricValue {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$response,
        [string]$metricPath
    )

    $metricParts = $metricPath -split '\.'
    $value = $response
    foreach ($part in $metricParts) {
        if ($null -ne $value) {
            $value = $value.PSObject.Properties[$part].Value
        } else {
            break
        }
    }
    return $value
}

# Función para limpiar las unidades de los valores
function Clean-MetricValue {
    param (
        [string]$value
    )

    if ($value -match 's$') {
        $value = [double]($value -replace '[^\d.]', '') * 1000  # Convertir segundos a milisegundos
    } elseif ($value -match 'ms$') {
        $value = [double]($value -replace '[^\d.]', '')  # Convertir milisegundos a número
    } elseif ($value -match '%$') {
        $value = [double]($value -replace '[^\d.]', '')  # Convertir porcentaje a número
    } elseif ($value -match 'm$') {
        $value = [double]($value -replace '[^\d.]', '') * 60000  # Convertir minutos a milisegundos
    } else {
        $value = [double]($value -replace '[^\d.]', '')  # Convertir cualquier otra unidad a número
    }
    return $value
}

# Iterar sobre cada dominio y obtener los datos de PageSpeed Insights API
foreach ($domain in $domains) {
    Write-Host "Analizando el dominio: ${domain}"
    $url = "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=${domain}"
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get

        # Crear un objeto para almacenar los resultados del dominio actual
        $result = [PSCustomObject]@{
            Domain = $domain
        }

        # Iterar sobre cada métrica y extraer el valor correspondiente
        foreach ($metric in $metrics) {
            $metricName = $metric -replace '[^a-zA-Z0-9]', '_'
            try {
                $metricValue = Get-MetricValue -response $response -metricPath $metric

                if (-not $metricValue) {
                    $metricValue = "N/A"  # Asignar "N/A" si el valor es nulo o vacío
                } else {
                    $metricValue = Clean-MetricValue -value $metricValue
                }

                Write-Host "Métrica: ${metricName}, Valor: ${metricValue}"
            } catch {
                $metricValue = "N/A"  # Manejar cualquier métrica no encontrada
                Write-Warning "Error al obtener la métrica ${metric} para el dominio ${domain}: $_"
            }

            if ($metricName -ne "") {
                $result | Add-Member -MemberType NoteProperty -Name $metricName -Value $metricValue
            } else {
                Write-Warning "Nombre de métrica vacío para ${metric} en ${domain}"
            }
        }

        # Evaluar y agregar la categoría de velocidad (FAST, SLOW)
        foreach ($metric in $metrics) {
            if ($metric -match '\.score$') {
                $metricScoreName = $metric -replace '[^a-zA-Z0-9]', '_'
                $metricDisplayName = $metric -replace '\.score$', '.displayValue'
                $metricScore = $result.$metricScoreName
                $metricValue = Get-MetricValue -response $response -metricPath $metricDisplayName

                if ($metricScore -ne "N/A" -and $metricScore -ne $null) {
                    if ($metricScore -ge 0.9) {
                        $category = "FAST"
                    } elseif ($metricScore -ge 0.5) {
                        $category = "MODERATE"
                    } else {
                        $category = "SLOW"
                    }
                    $result | Add-Member -MemberType NoteProperty -Name "$metricScoreName`_Category" -Value $category
                }

                # Mostrar recomendaciones específicas
                if ($metric -match 'lighthouseResult\.audits\..*\.details\.items') {
                    $recommendations = Get-MetricValue -response $response -metricPath $metric
                    foreach ($item in $recommendations) {
                        $recommendationText = $item | Select-Object -ExpandProperty explanation
                        if ($recommendationText) {
                            Write-Host "Recomendación para ${metric}: ${recommendationText}"
                        }
                    }
                }
            }
        }

        # Agregar el resultado a la lista de resultados
        $results += $result
    } catch {
        Write-Warning "Error al obtener los datos para el dominio ${domain}: $_"
    }
}

# Exportar los resultados a un archivo CSV
$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host "Los resultados han sido guardados en ${outputFile}"