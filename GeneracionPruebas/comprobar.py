import json


def main(ingresos:int, gastos:int, prestamo:int, cuotas:int) -> str:
    ingresos_netos = ingresos - gastos
    cuota = prestamo / cuotas
    umbral = 15
    if prestamo > 10000 or cuotas > 12:
        umbral = 40
    if cuota <= ((ingresos_netos * umbral) / 100):
        resultado = True
    else:
        resultado = False
    return resultado
def comprobar_casos_jsonl(nombre_archivo="pruebas.jsonl"):
    paso = 0
    fallo = 0
    with open(nombre_archivo, 'r') as f:
        for linea in f:
            caso = json.loads(linea)
            ingresos = caso["ingresos"]
            gastos = caso["gastos"]
            prestamo = caso["prestamo"]
            cuotas = caso["cuotas"]
            resultado = main(ingresos, gastos, prestamo, cuotas)
            if resultado:
                paso += 1
            else:
                fallo += 1
            print(f"Caso: {caso} - Resultado: {resultado}")
            print(f"Pasos: {paso} - Fallos: {fallo}")

comprobar_casos_jsonl()

