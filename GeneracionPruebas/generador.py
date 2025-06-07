import json
import random

def generar_casos_jsonl(num_casos, nombre_archivo="pruebas.jsonl"):
    with open(nombre_archivo, 'w') as f:
        for _ in range(num_casos):
            ingresos = random.randint(5000, 10000)
            prestamo = random.randint(1000, 15000)
            cuotas = random.choice([6, 10, 12, 18, 24, 30 ,36])
            cuota = prestamo // cuotas
            prestamo = cuota * cuotas
            caso = {
                "ingresos": ingresos,
                "gastos": random.randint(500, ingresos//2),
                "prestamo": prestamo,
                "cuotas": cuotas,
                "cuota": cuota,
            }
            f.write(json.dumps(caso) + '\n')
    
    print(f"Se generaron {num_casos} casos en {nombre_archivo}")

generar_casos_jsonl(100) 